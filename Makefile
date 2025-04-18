OUTPUT=typer

build:
	crystal build src/cli.cr -o $(OUTPUT) --error-trace --stats --progress

release:
	crystal build src/cli.cr -o $(OUTPUT) --error-trace --stats --progress --release

test:
	crystal spec --error-trace --stats

clean:
	rm $(OUTPUT)
