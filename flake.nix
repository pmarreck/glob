{
	description = "Explicit, controlled Bash pathname expansion";

	inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

	outputs = { self, nixpkgs }:
		let
			systems = [
				"x86_64-linux"
				"aarch64-linux"
				"aarch64-darwin"
			];
			forAllSystems = function:
				nixpkgs.lib.genAttrs systems (system: function system);
		in {
			packages = forAllSystems (system:
				let
					pkgs = nixpkgs.legacyPackages.${system};
					runtimeTools = [ pkgs.bash pkgs.coreutils ]
						++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.glibc.bin ];
					package = pkgs.stdenvNoCC.mkDerivation {
						pname = "glob";
						version = "0.1.0";
						src = ./.;
						strictDeps = true;
						nativeBuildInputs = [ pkgs.makeWrapper ];
						dontBuild = true;
						installPhase = ''
							runHook preInstall
							install -Dm755 bin/glob "$out/bin/glob"
							install -Dm644 src/expand_glob.bash "$out/share/glob/expand_glob.bash"
							install -Dm755 test "$out/share/glob/test"
							install -Dm755 tests/cli/glob_test "$out/share/glob/tests/cli/glob_test"
							install -Dm755 tests/compat/dotfiles_glob_test "$out/share/glob/tests/compat/dotfiles_glob_test"
							install -Dm755 tests/compat/dotfiles_no_compgen_test "$out/share/glob/tests/compat/dotfiles_no_compgen_test"
							patchShebangs "$out/bin/glob"
							wrapProgram "$out/bin/glob" \
								--prefix PATH : ${pkgs.lib.makeBinPath runtimeTools}
							runHook postInstall
						'';
						meta = {
							description = "Explicit, controlled Bash pathname expansion";
							homepage = "https://github.com/pmarreck/glob";
							license = pkgs.lib.licenses.mit;
							mainProgram = "glob";
							platforms = systems;
						};
					};
				in {
					default = package;
					glob = package;
				});

			apps = forAllSystems (system: {
				default = {
					type = "app";
					program = "${self.packages.${system}.default}/bin/glob";
					meta.description = "Explicit, controlled Bash pathname expansion";
				};
				glob = self.apps.${system}.default;
			});

			checks = forAllSystems (system:
				let
					pkgs = nixpkgs.legacyPackages.${system};
					testTools = [ pkgs.bash pkgs.coreutils pkgs.gnugrep ]
						++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.glibc.bin ];
				in {
					build = self.packages.${system}.default;
					test = pkgs.stdenvNoCC.mkDerivation {
						pname = "glob-tests";
						version = "0.1.0";
						src = ./.;
						strictDeps = true;
						nativeBuildInputs = testTools;
						dontBuild = true;
						doCheck = true;
						checkPhase = ''
							runHook preCheck
							patchShebangs bin/glob test tests/cli/glob_test tests/compat/dotfiles_glob_test tests/compat/dotfiles_no_compgen_test src/expand_glob.bash
							./test
							runHook postCheck
						'';
						installPhase = ''
							mkdir -p "$out"
							printf 'tests passed\n' > "$out/result"
						'';
					};
				});

			devShells = forAllSystems (system:
				let pkgs = nixpkgs.legacyPackages.${system};
				in {
					default = pkgs.mkShell {
						packages = [
							pkgs.bashInteractive
							pkgs.luajit
							pkgs.shellcheck
						];
					};
				});
		};
}
