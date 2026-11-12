APP := build/Apfellicht.app
QUIT = pkill -x -U "$$(id -u)" Apfellicht; sleep 0.5; true

.PHONY: build app run install status reset clean

build:
	swift build

app:
	scripts/build-app.sh

run: app
	$(QUIT)
	open $(APP)

## install: nach /Applications kopieren und starten
install: app
	$(QUIT)
	rm -rf /Applications/Apfellicht.app
	cp -R $(APP) /Applications/
	open /Applications/Apfellicht.app

status:
	swift run -c release apfellicht-cli status

## reset: Notfall, Apples Werkstabellen zurück
reset:
	swift run -c release apfellicht-cli reset

clean:
	rm -rf .build build
