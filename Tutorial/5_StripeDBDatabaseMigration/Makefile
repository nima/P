all:
	[ ! -e PCheckerOutput/BugFinding ] || rm -rf PCheckerOutput/BugFinding*
	p compile
	p check -tc tcMigrationPhases -s 1000 || jq -C . PCheckerOutput/BugFinding/Migration_0_0.trace.json

clean:
	-rm -rf PGenerated
