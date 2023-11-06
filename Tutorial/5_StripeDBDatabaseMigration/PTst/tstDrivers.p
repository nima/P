// vim:et:ts=2:sw=2

machine tdStripDBInterrogator {
  var f : Fleet;
  var c : Client;
  var req : tClientReq;
  var storage : map[tDatabaseStripe, map[int,int]];

  start state Init {
    entry {
      storage[StripeJ] = initializeStorage(5);
      storage[StripeD] = initializeStorage(0);

      f = new Fleet((
        jDB=new Database((stripe=StripeJ, ident="JournalDB", storage=storage[StripeJ])),
        dDB=new Database((stripe=StripeD, ident="DynamoDB", storage=storage[StripeD]))
      ));
      c = new Client((fleet=f, ));

      send c, eInvokeProcedure, updateLocalWithRandomKey(StripeJ, 200);

      announce eSpecStart, storage;
    }
  }

  // update a single key in storage (i.e., increment revesion), and return the key
  fun updateLocalWithRandomKey(dbid: tDatabaseStripe, hRange: int) : int {
    // TODO: this has to know if the operation is a CREAT or whatever, it can't just update the storage blindly
    var key : int;
    var rev : int;

    key = hRange + choose(100);
    if (key in storage[dbid]) rev = storage[dbid][key];
    else rev = 99999;

    storage[dbid][key] = rev + 1;

    return key;
  }

  fun initializeStorage(count: int) : map[int, int] {
    var store : map[int, int];

    while(count > 0) {
      store[100 + choose(100)] = 1 + choose(20);
      count = count - 1;
    }

    return store;
  }
}