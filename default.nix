{ lib, stdenvNoCC, makeWrapper, fzf, gum, chafa, gh, jq, glab }:

stdenvNoCC.mkDerivation rec {
  pname = "wt";
  version = "2.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -Dm755 wt.sh $out/bin/wt-core
    mkdir -p $out/lib
    cp lib/*.sh $out/lib/
    mkdir -p $out/assets
    cp assets/logo.png $out/assets/
    install -Dm644 completions/wt.zsh $out/share/zsh/site-functions/_wt
  '';

  postFixup = ''
    wrapProgram $out/bin/wt-core \
      --prefix PATH : ${lib.makeBinPath [ fzf gum chafa gh jq glab ]}
  '';

  meta = with lib; {
    description = "Git worktree manager with fzf integration and GitHub/GitLab support";
    homepage = "https://github.com/AThevon/wt";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "wt-core";
  };
}
