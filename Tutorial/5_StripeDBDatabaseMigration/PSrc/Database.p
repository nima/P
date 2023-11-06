// vim:et:ts=2:sw=2

enum tDatabaseStripe { StripeJ, StripeD }

// Not captured here is that CREATE is mutually exclusive, while the rest are
// priorities; that is o1111 means that JournalDB is the sole actor for CREATE,
// and the other operations will favor JournalDB but fallback to DynamoDB.
enum tDatabaseReqCode { SCAN = 16, CREATE = 8, READ = 4, UPDATE = 2, DELETE = 1 }
enum tDatabaseResCode { SUCCESS = 200, NOTFOUND = 404, ERROR = 500 }
enum tDatabaseSelectOverride { StripeDB = 0, JournalDB = 1, DynamoDB = 2 }
type tDatabaseReq = (requester: seq[machine], cfg: tFleetPhaseSet, key: int, op: tDatabaseReqCode, override: tDatabaseSelectOverride);
type tDatabaseRes = (db: Database, req: tDatabaseReq, payload: data, rev: int, code: tDatabaseResCode);

event eDatabaseReq : tDatabaseReq;
event eDatabaseRes : tDatabaseRes;

machine Database {
  var ident : string;
  var stripe : tDatabaseStripe;
  var storage : map[int, int];

  start state Init {
    entry (argv: (stripe: tDatabaseStripe, ident: string, storage: map[int, int])) {
      stripe = argv.stripe;
      ident = argv.ident;
      storage = argv.storage;

      goto Serve;
    }
  }

  state Serve {
    on eDatabaseReq do (req: tDatabaseReq) {
      if (req.op == SCAN) respond(craftSCANPayload(req));
      else respond(craftCRUDPayload(req));
    }
  }
  
  fun respond(res: tDatabaseRes) {
    var requester : machine;

    requester = res.req.requester[0];
    res.req.requester -= (0);

    send requester, eDatabaseRes, res;
  }

  fun craftSCANPayload(req: tDatabaseReq) : tDatabaseRes {
    var res : tDatabaseRes;

    assert(req.override != StripeDB);

    res.db = this;
    res.req = req;
    res.rev = req.key;
    res.payload = storage as map[int, int];
    res.code = SUCCESS;

    return res;
   }

  fun craftCRUDPayload(req: tDatabaseReq) : tDatabaseRes {
    var res : tDatabaseRes;
    var exists : bool;

    res.code = ERROR;
    res.db = this;
    res.req = req;
    res.rev = -1;
    res.payload = null as data;

    exists = (res.rev > 0);

    if (req.op == CREATE) {
      if (!exists) {
        if (!(req.key in storage)) {
          storage[req.key] = 1;
          res.payload = req.key as int;
          res.rev = storage[req.key];
          res.code = SUCCESS;
        } else {
          res.code = ERROR;
        }
      }
    } else if (req.op == READ) {
      if (exists) {
        res.payload = req.key as int;
        res.rev = storage[req.key];
        res.code = SUCCESS;
      } else {
        res.code = NOTFOUND;
      }
    } else if (req.op == UPDATE) {
      if (exists) {
        storage[req.key] = storage[req.key] + 1;
        res.payload = req.key as int;
        res.rev = storage[req.key];
        res.code = SUCCESS;
      } else {
        res.code = NOTFOUND;
      }
    } else if (req.op == DELETE) {
      if (exists) {
        res.rev = storage[req.key];
        res.payload = req.key as int;
        storage -= req.key;
        res.code = SUCCESS;
      } else {
        res.code = NOTFOUND;
      }
    }

    return res;
  }
}
