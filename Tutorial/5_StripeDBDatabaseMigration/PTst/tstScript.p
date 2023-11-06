// vim:et:ts=2:sw=2

test tcMigrationPhases [main=tdStripDBInterrogator]:
  assert StripeDBSpec in (
    union ModMigration, ModClient, { tdStripDBInterrogator }
  );