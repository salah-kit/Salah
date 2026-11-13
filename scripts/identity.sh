# shellcheck shell=bash disable=SC2034
# Salah's own identifiers, sourced by the scripts here. They build Salah under these
# whatever Config/Local.xcconfig names, as they build without its team, so their checks
# and simctl commands can name the apps.
bundle_identifier=io.github.salah-kit.Salah
app_group=group.io.github.salah-kit.Salah.shared
identity=(APP_BUNDLE_IDENTIFIER="$bundle_identifier" APP_GROUP_IDENTIFIER="$app_group")
