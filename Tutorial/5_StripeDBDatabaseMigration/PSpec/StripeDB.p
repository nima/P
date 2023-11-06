// vim:et:ts=2:sw=2

event eSpecStripeDBListenForAnnouncement : map[tDatabaseStripe, map[int, int]];

spec StripeDBSpec observes eSpecStripeDBListenForAnnouncement, eClientRes {
  var shadowDB : map[tDatabaseStripe, map[int, int]];

  start state Monitor {
    on eSpecStripeDBListenForAnnouncement goto validateAllClientResponses with (storage: map[tDatabaseStripe, map[int, int]]) {
      shadowDB = storage;
    }
    on eClientRes do (res: tDatabaseRes) {
      if (res.req.op == SCAN) {
        raise eCriticalFault, (999, format("SCAN responses should never make it to Monitor"));
      }
    }
  }

  // any transaction from the client, when responded to, should immediately be validated for correctness
  state validateAllClientResponses {
    on eClientRes do (res: tDatabaseRes) {
      if (res.req.op == SCAN && res.req.override == JournalDB) {
        assert res.payload == shadowDB[StripeJ], format(
          "expected: {0}, received: {1}", shadowDB[StripeJ], res.payload
        );
      } else if (res.req.op == SCAN && res.req.override == DynamoDB) {
        assert res.payload == shadowDB[StripeD], format(
          "expected: {0}, received: {1}", shadowDB[StripeD], res.payload
        );
      }
      goto Monitor;
    }
  }
}