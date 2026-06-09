# CLIProxyAPI — prebuilt release binary.
#
# Local OAuth proxy that exposes OpenAI/Gemini/Claude-compatible endpoints, used
# by Ephemera's "Login" (browser OAuth) auth mode. Ephemera runs it on demand.
#
# To update: bump `version` + `sha256` (the linux_amd64 release tarball's sha256,
# e.g. `nix-prefetch-url <url>` or `sha256sum` on the downloaded tarball).
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}: let
  version = "7.1.58";
in
  stdenv.mkDerivation {
    pname = "cliproxyapi";
    inherit version;

    src = fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${version}/CLIProxyAPI_${version}_linux_amd64.tar.gz";
      sha256 = "05f32c62c445985a19aae7a2b97c535c445e6d58b7ab8deab2593915a2e98610";
    };

    # Tarball expands loose files (no top-level dir).
    sourceRoot = ".";

    nativeBuildInputs = [autoPatchelfHook];
    buildInputs = [stdenv.cc.cc.lib];

    installPhase = ''
      runHook preInstall
      install -Dm755 cli-proxy-api $out/bin/cli-proxy-api
      runHook postInstall
    '';

    meta = {
      description = "Local proxy exposing OpenAI/Gemini/Claude-compatible endpoints with OAuth login";
      homepage = "https://github.com/router-for-me/CLIProxyAPI";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux"];
      mainProgram = "cli-proxy-api";
    };
  }
