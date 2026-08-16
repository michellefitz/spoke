#!/bin/sh
# Xcode Cloud runs this right after cloning. Spoke/Config.swift is gitignored
# (it holds secrets), so the clone doesn't have it and the archive fails with
# "Build input file cannot be found". Generate it here instead, reading the
# proxy details from the workflow's environment variables — set them in
# App Store Connect > Xcode Cloud > Workflow > Environment Variables
# (SPOKE_PROXY_BASE_URL, and SPOKE_PROXY_SECRET marked secret). With no
# variables set the build still succeeds; the archive just can't parse.
set -e

cat > "$CI_PRIMARY_REPOSITORY_PATH/Spoke/Config.swift" <<SWIFT
enum Config {
    static let proxyBaseURL = "${SPOKE_PROXY_BASE_URL:-}"
    static let proxySecret  = "${SPOKE_PROXY_SECRET:-}"

    // Never populated on CI — keys stay server-side behind the proxy.
    static let anthropicAPIKey = ""
    static let deepgramAPIKey  = ""
}
SWIFT

echo "Generated Spoke/Config.swift (proxyBaseURL set: ${SPOKE_PROXY_BASE_URL:+yes}${SPOKE_PROXY_BASE_URL:-no})"
