{
	description = "Explicit pathname expansion backed by globlike";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
		zig-overlay = {
			url = "github:mitchellh/zig-overlay/5b4b89d060609b448df810bc55f04d003089237a";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};

	outputs = { self, nixpkgs, zig-overlay }:
		let
			systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
			forAllSystems = function: nixpkgs.lib.genAttrs systems (system: function system);
			products = system:
				let
					pkgs = nixpkgs.legacyPackages.${system};
					zig = zig-overlay.packages.${system}."0.16.0";
					source = self;
					zigDeps = pkgs.stdenv.mkDerivation {
						pname = "glob-zig-deps";
						version = "0.2.0";
						src = source;
						nativeBuildInputs = [ zig pkgs.git pkgs.cacert ];
						outputHashMode = "recursive";
						outputHashAlgo = "sha256";
						outputHash = "sha256-yA9uVSSIvZscrL30qyVzy/LnZIS7F5suQHOhm15mukQ=";
						dontConfigure = true;
						dontFixup = true;
						buildPhase = ''
							export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-fetch
							export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
							export GIT_SSL_CAINFO=$SSL_CERT_FILE
							zig build --fetch=all
						'';
						installPhase = ''
							mkdir -p "$out"
							cp -R "$ZIG_GLOBAL_CACHE_DIR/p" "$out/p"
						'';
					};
					engine = pkgs.stdenv.mkDerivation {
						pname = "glob-engine";
						version = "0.2.0";
						src = source;
						strictDeps = true;
						nativeBuildInputs = [ zig ];
						dontConfigure = true;
						buildPhase = ''
							runHook preBuild
							export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
							mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
							cp -R ${zigDeps}/p "$ZIG_GLOBAL_CACHE_DIR/"
							chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR"
							zig build -Doptimize=ReleaseFast --prefix "$out" ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux "-Dtarget=${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux-musl"}
							runHook postBuild
						'';
						installPhase = "true";
					};
					runtimeTools = [ pkgs.bash pkgs.coreutils ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.glibc.bin ];
					package = pkgs.stdenvNoCC.mkDerivation {
						pname = "glob";
						version = "0.2.0";
						src = self;
						strictDeps = true;
						nativeBuildInputs = [ pkgs.bash ];
						dontBuild = true;
						installPhase = ''
							runHook preInstall
							install -Dm755 bin/glob "$out/bin/glob"
							install -Dm755 ${engine}/bin/glob-engine "$out/libexec/glob/glob-engine"
							install -Dm755 test "$out/share/glob/test"
							install -Dm755 tests/cli/glob_test "$out/share/glob/tests/cli/glob_test"
							install -Dm755 tests/compat/dotfiles_glob_test "$out/share/glob/tests/compat/dotfiles_glob_test"
							install -Dm755 tests/compat/dotfiles_no_compgen_test "$out/share/glob/tests/compat/dotfiles_no_compgen_test"
							substituteInPlace "$out/bin/glob" \
								--replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash
							PATH=${pkgs.lib.makeBinPath runtimeTools}:$PATH
							export PATH'
							for script in "$out/share/glob/test" "$out/share/glob/tests/cli/glob_test" "$out/share/glob/tests/compat/dotfiles_glob_test" "$out/share/glob/tests/compat/dotfiles_no_compgen_test"; do
								substituteInPlace "$script" --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
							done
							runHook postInstall
						'';
						meta = {
							description = "Explicit pathname expansion backed by globlike";
							homepage = "https://github.com/pmarreck/glob";
							license = pkgs.lib.licenses.mit;
							mainProgram = "glob";
							platforms = systems;
						};
					};
					testTools = [ pkgs.bash pkgs.coreutils pkgs.gnugrep ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.glibc.bin ];
					test = pkgs.stdenvNoCC.mkDerivation {
						pname = "glob-tests";
						version = "0.2.0";
						src = self;
						strictDeps = true;
						nativeBuildInputs = testTools;
						dontBuild = true;
						doCheck = true;
						GLOB_ENGINE = "${engine}/bin/glob-engine";
						checkPhase = ''
							runHook preCheck
							patchShebangs bin/glob test tests/cli/glob_test tests/compat/dotfiles_glob_test tests/compat/dotfiles_no_compgen_test
							./test
							${package}/bin/glob --about >/dev/null
							${package}/bin/glob --test
							runHook postCheck
						'';
						installPhase = ''
							mkdir -p "$out"
							printf 'tests passed\n' > "$out/result"
						'';
					};
				in { inherit engine package test; };
		in {
			packages = forAllSystems (system: let built = products system; in {
				default = built.package;
				glob = built.package;
				engine = built.engine;
			});
			apps = forAllSystems (system: {
				default = { type = "app"; program = "${self.packages.${system}.default}/bin/glob"; meta.description = "Explicit pathname expansion backed by globlike"; };
				glob = self.apps.${system}.default;
			});
			checks = forAllSystems (system: let built = products system; in { build = built.package; test = built.test; });
			devShells = forAllSystems (system: let pkgs = nixpkgs.legacyPackages.${system}; in {
				default = pkgs.mkShell {
					packages = [ pkgs.bashInteractive pkgs.luajit pkgs.shellcheck zig-overlay.packages.${system}."0.16.0" ];
				};
			});
		};
}
