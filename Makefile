# Developer shortcuts. Installing doesn't need any of this: see README.md.
.PHONY: build panel dist release test lint install uninstall clean

build:            ## rexmod CLI into build/ (what ~/.local/bin/rexmod points to while developing)
	cd cmd/rexmod && go build -o ../../build/rexmod .

panel:            ## panel dylib straight into the install; restart Rex to load it
	panel/build.sh

dist:             ## prebuilt files install.sh ships (arm64, macOS 15+)
	scripts/build-dist.sh

release:          ## release tarball in build/release
	scripts/package-release.sh

test:
	cd cmd/rexmod && go vet ./... && go test ./...

lint:
	shellcheck -s sh install.sh uninstall.sh scripts/*.sh panel/build.sh
	gofmt -l cmd

install: dist
	./install.sh

uninstall:
	"$(HOME)/Library/Application Support/rexmod/scripts/uninstall.sh"

clean:
	rm -rf build dist
