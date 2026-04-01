{ lib, stdenvNoCC, makeWrapper, fzf, gum, gh, jq, glab }:

stdenvNoCC.mkDerivation rec {
  pname = "worktigre";
  version = "2.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -Dm755 wt.sh $out/bin/wt-core
    mkdir -p $out/lib/worktigre
    cp lib/*.sh $out/lib/worktigre/
    mkdir -p $out/assets/worktigre
    cp assets/logo*.ansi $out/assets/worktigre/
    install -Dm644 completions/wt.zsh $out/share/zsh/site-functions/_wt
  '';

  postFixup = ''
    wrapProgram $out/bin/wt-core \
      --prefix PATH : ${lib.makeBinPath [ fzf gum gh jq glab ]}
  '';

  meta = with lib; {
    description = "Git worktree manager with fzf integration and GitHub/GitLab support";
    homepage = "https://github.com/AThevon/worktigre";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "wt-core";
  };
}
