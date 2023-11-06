// vim:et:ts=2:sw=2

machine tdStripDBInterrogator {
  var f : Fleet;
  var c : Client;
  var req : tClientReq;
  var storage : map[tDatabaseStripe, map[int,int]];
  var migrationPhases : seq[tMigrationPhaseFleetSet];

  start state Init {
    entry {
      initializeStorage(StripeJ, 5);
      initializeStorage(StripeD, 0);

      f = new Fleet((
        jDB=new Database((stripe=StripeJ, ident="JournalDB", storage=storage[StripeJ])),
        dDB=new Database((stripe=StripeD, ident="DynamoDB", storage=storage[StripeD]))
      ));
      c = new Client((fleet=f, ));

      initializeMigrationPhases();
      send f, eFleetPhaseChange, migrationPhases[0];
      migrationPhases -= (0);

      goto startMigration;
    }
  }

  state startMigration {
    entry {
      generateRandomRequestThenUpdateLocalStorageThenRequestToProxy();
    }

    on eClientRes do (res: tDatabaseRes) {
      print format("{0}", res);
    }
  }
  
  fun initializeStorage(stripe: tDatabaseStripe, count: int) {
    var store: map[int, int];
    storage[stripe] = store;
    while(count > 0) {
      storage[stripe][100 + choose(100)] = 1 + choose(20);
      count = count - 1;
    }
  }

  fun initializeMigrationPhases() {
    var nextPhaseSet: set[tFleetPhaseId];

    nextPhaseSet += (B0); migrationPhases += (sizeof(migrationPhases), nextPhaseSet); // [B0]
    nextPhaseSet += (B1); migrationPhases += (sizeof(migrationPhases), nextPhaseSet); // [B0, B1]
    nextPhaseSet -= (B0); migrationPhases += (sizeof(migrationPhases), nextPhaseSet); //     [B1]
    nextPhaseSet += (B2); migrationPhases += (sizeof(migrationPhases), nextPhaseSet); //     [B1, B2]
    nextPhaseSet -= (B1); migrationPhases += (sizeof(migrationPhases), nextPhaseSet); //         [B2]
    nextPhaseSet += (B3); migrationPhases += (sizeof(migrationPhases), nextPhaseSet); //         [B2, B3]
    nextPhaseSet -= (B2); migrationPhases += (sizeof(migrationPhases), nextPhaseSet); //             [B3]
  }

  // update a single key in storage (i.e., increment revesion), and return the key
  fun generateRandomRequestThenUpdateLocalStorageThenRequestToProxy() {
    var key : int;
    var rev : int;
    var req : tClientReq;

    key = 500 + choose(100);
    if (key in storage[StripeJ]) {
      // TODO: UPDATE, DELETE, or READ
      rev = storage[StripeJ][key];
    } else {
      // CREATE
      storage[StripeJ][key] = 1;
      req = mkCreateRequest(this, key);
    }

    announce eSpecStripeDBListenForAnnouncement, storage;
    assert sizeof(req.requesters) == 1 && req.requesters[0] == this, format(
      "Expected a single requester ({0}) in requesters, received instead: {1}", this, req.requesters
    );
    send c, eClientReq, req;
  }

  fun mkCreateRequest(requester: machine, key: int) : tClientReq {
    var req : tClientReq;

    req.op = CREATE;
    req.requesters += (0, requester);
    assert sizeof(req.requesters) == 1, format("{0}", req.requesters); // [this, testSuite]
    req.key = key;

    assert req.override == StripeDB, format("CREATE operation expects <StripeDB:{0}>, but found <?:{1}>", StripeDB, req.override);
    return req;
  }
}