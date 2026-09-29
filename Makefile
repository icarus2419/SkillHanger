.PHONY: build test app clean

build:
	swift build

test:
	swift test

app:
	swift build -c release
	python3 scripts/package-app.py
	codesign --verify --deep --strict dist/SkillHanger.app

clean:
	rm -rf dist
