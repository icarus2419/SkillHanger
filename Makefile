.PHONY: build test app release clean

build:
	swift build

test:
	swift test

app:
	swift build -c release
	python3 scripts/package-app.py
	codesign --verify --deep --strict dist/SkillHanger.app

release: app
	ditto -c -k --keepParent dist/SkillHanger.app dist/SkillHanger-$$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist).zip

clean:
	rm -rf dist
