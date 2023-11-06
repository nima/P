// vim:et:ts=2:sw=2

event eCriticalFault : (int, string);
event eNotImplemented : int;

enum tFleetPhaseId { B0 = 0, B1 = 1, B2 = 2, B3 = 3 }
type tFleetDatabaseConfig = (C: bool, R: bool, U: bool, D: bool);
type tFleetPhaseSet = (JournalDB: tFleetDatabaseConfig, DynamoDB: tFleetDatabaseConfig);
type tMigrationPhaseFleetSet = set[tFleetPhaseId];

event eFleetPhaseChange : tMigrationPhaseFleetSet;

machine Fleet {
  var fleetSet : set[tFleetPhaseId];

  // The feature flags on any given "fleet" determins the abstract notion of
  // the "stripe database", therefore we code that up in this state machine.
  var journalDB : Database;
  var dynamoDB : Database;

  start state Init {
    entry (argv: (jDB: Database, dDB: Database)) {
      journalDB = argv.jDB;
      dynamoDB = argv.dDB;

      goto BlockOnFirstDeployment;
    }
  }

  state BlockOnFirstDeployment {
    on eFleetPhaseChange do (fs: tMigrationPhaseFleetSet) {
      fleetSet = fs;
      goto Serve;
    }
  }

  state Serve {
    on eFleetPhaseChange do (fs: tMigrationPhaseFleetSet) {
      fleetSet = fs;
    }

    // 110s
    on eDatabaseReq do (req: tDatabaseReq) {
      req.requesters += (0, this);
      assert sizeof(req.requesters) == 3 && req.requesters[0] == this, format("Expected X but got {0}", req.requesters); // [this, client, testSuite]

      if (req.op == CREATE) {
        if (req.cfg.JournalDB.C) {
          send journalDB, eDatabaseReq, req;
        } else if (req.cfg.DynamoDB.C) {
          send dynamoDB, eDatabaseReq, req;
        }
      } else if (req.op == READ) {
        if (req.cfg.JournalDB.C) {
          send journalDB, eDatabaseReq, req;
        } else if (req.cfg.DynamoDB.C) {
          send dynamoDB, eDatabaseReq, req;
        }
      } else {
        raise eNotImplemented, 118;
      }
    }

    // 100s
    on eDatabaseRes do (res: tDatabaseRes) {
      assert (
        sizeof(res.req.requesters) == 2 && res.req.requesters[0] != this
      ), format(
        "Expected 2 entries, and the first to not be {0}, but found {1}", this, res.req.requesters
      ); // [c, td]

      if (res.code == NOTFOUND) {
        if (res.req.op == READ) {
          // Stripe search; bounce back to the database layer, this time, the alternate stripe
          res.req.requesters += (0, this);
          if (res.req.cfg.JournalDB.R) {
            send dynamoDB, eDatabaseReq, res.req;
          } else if (res.req.cfg.DynamoDB.R) {
            send journalDB, eDatabaseReq, res.req;
          }
        } else {
          raise eNotImplemented, 101;
        }
      } else if (res.code == SUCCESS) {
        assert (
          sizeof(res.req.requesters) == 2 && res.req.requesters[0] != this
        ), format(
          "Expected 2 entries, and the first to not be {0}, but instead found {1}", this, res.req.requesters
        ); // [c, td]
        send res.req.requesters[0], eDatabaseRes, res;
      } else if (res.code == ERROR) {
        // errors are normal DB functions, will not raise anything here.
        send res.req.requesters[0], eDatabaseRes, res;
      }
    }
  }

  fun handleRequest(req: tDatabaseReq) {
    if (req.op == SCAN) {
      assert req.override != StripeDB, format("Expected anything but {0}, but found {1}", StripeDB, req.override);
    } else {
      assert req.override == StripeDB, format("Expected {0}, but found {1}", StripeDB, req.override);
    }
    assert sizeof(req.requesters) == 2 && req.requesters[0] == this, format("Expected a size 2 array, the first of which to be <this:{0}>, but found instead: {1}", this, req.requesters);

    if (req.op == SCAN) {
      if (req.override == JournalDB) {
        send journalDB, eDatabaseReq, req;
      } else if (req.override == DynamoDB) {
        send dynamoDB, eDatabaseReq, req;
      } else {
        raise eCriticalFault, (111, "Bad SCAN request");
      }
    } else if (req.op == CREATE) {
      if (req.cfg.JournalDB.C) {
        send journalDB, eDatabaseReq, req;
      } else if (req.cfg.DynamoDB.C) {
        send dynamoDB, eDatabaseReq, req;
      } else {
        raise eCriticalFault, (112, "Bad CREATE request");
      }
    } else if (req.op == READ) {
      if (req.cfg.JournalDB.C) {
        send journalDB, eDatabaseReq, req;
      } else if (req.cfg.DynamoDB.C) {
        send dynamoDB, eDatabaseReq, req;
      } else {
        raise eCriticalFault, (113, "Bad READ request");
      }
    } else {
      raise eCriticalFault, (119, "Bad UNKNOWN request");
    }
  }
}

fun MkFleetPhaseSet(jC: int, jR: int, jU: int, jD: int, dC: int, dR: int, dU: int, dD: int) : tFleetPhaseSet {
  var phase : tFleetPhaseSet;

  phase.JournalDB.C  = jC == 1;
  phase.JournalDB.R  = jR == 1;
  phase.JournalDB.U  = jU == 1;
  phase.JournalDB.D  = jD == 1;

  phase.DynamoDB.C = dC == 1;
  phase.DynamoDB.R = dR == 1;
  phase.DynamoDB.U = dU == 1;
  phase.DynamoDB.D = dD == 1;

  return phase;
}