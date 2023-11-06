// vim:et:ts=2:sw=2

event eCriticalFault : (int, string);
event eNotImplemented : int;

enum tApolloDeploymentState { COMPLETE, IN_PROGRESS }
event eApolloDeployment : tApolloDeploymentState;

enum tFleetPhaseId { B0 = 0, B1 = 1, B2 = 2, B3 = 3 }

type tFleetDatabaseConfig = (C: bool, R: bool, U: bool, D: bool);
type tFleetPhaseSet = (JournalDB: tFleetDatabaseConfig, DynamoDB: tFleetDatabaseConfig);

machine Fleet {
  var PHASES : map[tFleetPhaseId, tFleetPhaseSet];
  var fleetSet : set[tFleetPhaseId];

  // The feature flags on any given "fleet" determins the abstract notion of
  // the "stripe database", therefore we code that up in this state machine.
  var journalDB : Database;
  var dynamoDB : Database;

  start state Init {
    entry (argv: (jDB: Database, dDB: Database)) {
      PHASES = mkFleetPhaseSets();
      fleetSet += (B0);

      journalDB = argv.jDB;
      dynamoDB = argv.dDB;

      goto Serve;
    }
  }

  state Serve {
    on eApolloDeployment do (msg: tApolloDeploymentState) {
      if (msg == IN_PROGRESS) {
        fleetSet += (B1);
        send this, eApolloDeployment, COMPLETE;
      } else if (msg == COMPLETE) {
        fleetSet -= (B0);
        send this, eApolloDeployment, IN_PROGRESS;
      }
    }

    // 110s
    on eClientReq do (cliReq: tClientReq) {
      handleRequest(mkDatabaseRequest(cliReq));
    }

    on eDatabaseReq do (req: tDatabaseReq) {
      req.requester += (0, this);
      assert sizeof(req.requester) == 2 && req.requester[0] == this;

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
        sizeof(res.req.requester) == 1 && res.req.requester[0] != this
      ), format(
        "Expected 1 entry, and it to not be {0}, but found {1}", this, res.req.requester
      );

      if (res.code == NOTFOUND) {
        if (res.req.op == READ) {
          // Stripe search; bounce back to the database layer, this time, the alternate stripe
          res.req.requester += (0, this);
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
          sizeof(res.req.requester) == 1 && res.req.requester[0] != this
        ), format(
          "Expected 1 entry, and it to not be {0}, but found {1}", this, res.req.requester
        );
        send res.req.requester[0], eClientRes, res;
      } else if (res.code == ERROR) {
        // errors are normal DB functions, will not raise anything here.
        send res.req.requester[0], eClientRes, res;
      }
    }
  }

  fun handleRequest(req: tDatabaseReq) {
    if (req.op == SCAN) {
      assert req.override != StripeDB, format("Expected anything but {0}, but found {1}", StripeDB, req.override);
    } else {
      assert req.override == StripeDB, format("Expected {0}, but found {1}", StripeDB, req.override);
    }
    assert sizeof(req.requester) == 2 && req.requester[0] == this;

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


  fun mkDatabaseRequest(cliReq: tClientReq) : tDatabaseReq {
    var dbReq : tDatabaseReq;

    dbReq.requester += (0, cliReq.requester);
    dbReq.requester += (0, this);
    dbReq.key = cliReq.key;
    dbReq.op = cliReq.op;
    dbReq.override = cliReq.override;
    dbReq.cfg = PHASES[choose(fleetSet)];

    return dbReq;
  }
}

fun mkFleetPhaseSets() : map[tFleetPhaseId, tFleetPhaseSet] {
  var phases : map[tFleetPhaseId, tFleetPhaseSet];

  phases[B0] = mkFleetPhaseSet(1, 1, 1, 1, 0, 0, 0, 0); // JournalDB:[CRUD], DynamoDB:[----]
  phases[B1] = mkFleetPhaseSet(1, 0, 1, 1, 0, 1, 0, 0); // JournalDB:[CrUD], DynamoDB:[-Rud]
  phases[B2] = mkFleetPhaseSet(0, 0, 1, 1, 1, 1, 0, 0); // JournalDB:[-rUD], DynamoDB:[CRud]
  phases[B3] = mkFleetPhaseSet(0, 0, 0, 0, 1, 1, 1, 1); // JournalDB:[----], DynamoDB:[CRUD]

  return phases;
}

fun mkFleetPhaseSet(jC: int, jR: int, jU: int, jD: int, dC: int, dR: int, dU: int, dD: int) : tFleetPhaseSet {
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