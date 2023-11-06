// vim:et:ts=2:sw=2

type tClientReq = (requesters: seq[machine], key: int, op: tDatabaseReqCode, override: tDatabaseSelectOverride);
event eClientReq : tClientReq;
event eClientRes : tDatabaseRes;

machine Client receives eClientReq, eDatabaseRes;
sends eDatabaseReq, eClientRes;
{
  var fleet : Fleet;

  start state Init {
    entry (argv: (fleet: Fleet)) {
      fleet = argv.fleet;
      goto Proxy;
    }
  }

  state Proxy {
    on eClientReq do (req: tClientReq) {
      assert sizeof(req.requesters) == 1, format("{0}", req.requesters); // [td]

      sendRequest(req);

      if(req.override != StripeDB)
        sendRequest(mkScanRequest(req.override));
    }

    on eDatabaseRes do (res: tDatabaseRes) {
      assert sizeof(res.req.requesters) == 2, format("{0}", res.req.requesters); // [c, td];
      send res.req.requesters[1], eClientRes, res;
    }
  }

  fun sendRequest(req: tClientReq) {
    send fleet, eDatabaseReq, mkDatabaseRequest(req);
  }

  fun mkScanRequest(override: tDatabaseSelectOverride) : tClientReq {
    var req : tClientReq;

    req.requesters += (0, this);
    assert sizeof(req.requesters) == 2, format("{0}", req.requesters); // [this, testSuite]
    req.override = override;
    req.op = SCAN;
    req.key = -1;

    assert req.override != StripeDB, format("Expected anything but {0}, but found {1}", StripeDB, req.override);
    return req;
  }

  fun mkDatabaseRequest(cliReq: tClientReq) : tDatabaseReq {
    var dbReq : tDatabaseReq;
    var phases : map[tFleetPhaseId, tFleetPhaseSet];

    dbReq.requesters = cliReq.requesters;
    dbReq.requesters += (0, this);
    assert sizeof(dbReq.requesters) == 2, format("{0}", dbReq.requesters); // [this, testSuite]
    dbReq.key = cliReq.key;
    dbReq.op = cliReq.op;
    dbReq.override = cliReq.override;

    phases = MkFleetPhaseSets();
    dbReq.cfg = phases[B0]; // FIXME: hardcoded

    return dbReq;
  }

  fun MkFleetPhaseSets() : map[tFleetPhaseId, tFleetPhaseSet] {
    var phases : map[tFleetPhaseId, tFleetPhaseSet];

    phases[B0] = MkFleetPhaseSet(1, 1, 1, 1, 0, 0, 0, 0); // JournalDB:[CRUD], DynamoDB:[----]
    phases[B1] = MkFleetPhaseSet(1, 0, 1, 1, 0, 1, 0, 0); // JournalDB:[CrUD], DynamoDB:[-Rud]
    phases[B2] = MkFleetPhaseSet(0, 0, 1, 1, 1, 1, 0, 0); // JournalDB:[-rUD], DynamoDB:[CRud]
    phases[B3] = MkFleetPhaseSet(0, 0, 0, 0, 1, 1, 1, 1); // JournalDB:[----], DynamoDB:[CRUD]

    return phases;
  }
}