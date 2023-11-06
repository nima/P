// vim:et:ts=2:sw=2

event eSpecStart : map[tDatabaseStripe, map[int, int]];

spec StripeDBSpec observes eSpecStart, eClientRes {
  var shadowDB : map[tDatabaseStripe, map[int, int]];

  start state Monitor {
    on eSpecStart goto validateAllClientResponses with (storage: map[tDatabaseStripe, map[int, int]]) {
      shadowDB = storage;
    }
  }

  // any transaction from the client, when responded to, should immediately be validated for correctness
  state validateAllClientResponses {
    on eClientRes do (res: tDatabaseRes) {
      if (res.req.op == SCAN && res.req.override == JournalDB)
        assert res.payload == shadowDB[StripeJ], format("expected: {0}, received: {1}", shadowDB[StripeJ], res.payload);
    }
  }
}