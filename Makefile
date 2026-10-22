VERSION ?= 1.0.0
APP = build/NotchClaude.app

.PHONY: build test app dmg install run clean

build:
	swift build

test:
	swift test

app:
	VERSION=$(VERSION) ./Scripts/build-app.sh

dmg: app
	VERSION=$(VERSION) ./Scripts/make-dmg.sh

install: app
	-pkill -x NotchClaude
	rm -rf /Applications/NotchClaude.app
	cp -R $(APP) /Applications/
	open /Applications/NotchClaude.app

run: app
	-pkill -x NotchClaude
	open $(APP)

clean:
	rm -rf .build build dist
