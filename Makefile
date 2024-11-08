OUTPUT=typer

build:
	crystal build src/cli.cr -o $(OUTPUT) --error-trace --stats --progress

test:
	crystal spec --error-trace --stats

clean:
	rm $(OUTPUT)
