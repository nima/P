// vim:et:ts=2:sw=2

type tClientReq = (requester: machine, key: int, op: tDatabaseReqCode, override: tDatabaseSelectOverride);

event eClientReq : tClientReq;
event eClientRes : tDatabaseRes;

event eInvokeProcedure : int;

machine Client
  receives eInvokeProcedure, eClientRes;
sends eClientReq;
{
  var fleet : Fleet;

  start state Init {
    entry (argv: (fleet: Fleet)) {
      fleet = argv.fleet;
      goto Serve;
    }
  }

  // why does a client serve? because this is a zombie client; that is,
  // it's controlled by the test driver, who has full control over this
  // client.
  state Serve {
    on eInvokeProcedure do (key: int) {
      if (key > 0) {
        invokeProcedure(key);
      } else {
        raise eCriticalFault, 601, format("artificial enforcement of key > 0 not honored by caller; key: {0}", key);
      }
    }

    on eClientRes do (res: tDatabaseRes) {
      print format("response: {0}", res);
    }
  }

  fun invokeProcedure(key: int) {
    request(mkCreateRequest(key));
    request(mkScanRequest(JournalDB));
    request(mkScanRequest(DynamoDB));
  }
    
  fun request(req: tClientReq) {
    send fleet, eClientReq, req;
  }

  fun mkCreateRequest(key: int) : tClientReq {
    var req : tClientReq;

    req.op = CREATE;
    req.requester = this;
    req.key = key;

    assert req.override == StripeDB, format("CREATE operation expects <StripeDB:{0}>, but found <?:{1}>", StripeDB, req.override);
    return req;
  }

  fun mkScanRequest(override: tDatabaseSelectOverride) : tClientReq {
    var req : tClientReq;

    req.requester = this;
    req.override = override;
    req.op = SCAN;
    req.key = -1;

    assert req.override != StripeDB, format("Expected anything but {0}, but found {1}", StripeDB, req.override);
    return req;
  }
}

