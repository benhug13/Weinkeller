#!/bin/sh
set -e

# Xcode Cloud: laeuft nach dem Klonen, vor dem Bauen.
# Erzeugt Weinkeller.xcodeproj aus project.yml und setzt die Build-Nummer.

echo "xcodegen installieren..."
brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Build-Nummer = Xcode-Cloud-Run-Nummer (dort eindeutig, anders als die Commit-Anzahl).
BUILD_NUMBER="${CI_BUILD_NUMBER:-1}"
echo "Build-Nummer: $BUILD_NUMBER"
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml

# Kennung für den Vinello-Server. Liegt nicht im (öffentlichen) Repo, sondern als
# Umgebungsvariable VINELLO_APP_KEY im Xcode-Cloud-Workflow.
if [ ! -f Weinkeller/Services/Secrets.swift ]; then
  mkdir -p Weinkeller/Services
  printf 'enum Secrets {\n    static let vinelloAppKey = "%s"\n}\n' "${VINELLO_APP_KEY:-}" > Weinkeller/Services/Secrets.swift
fi

echo "Projekt erzeugen..."
xcodegen generate

echo "bereit"
