# For NixOS users with classic nix-shell (no flakes required).
{ pkgs ? import <nixpkgs> {} }:
let
  ovmf = pkgs.OVMF.override {
    secureBoot = true;
    fdSize4MB = true;
    msVarsTemplate = false;
  };
in pkgs.mkShell {
  packages = with pkgs; [
    qemu
    openssl
    sbsigntool
    python3Packages.virt-firmware
  ];

  shellHook = ''
    export OVMF_CODE="${ovmf.firmware}"
    export OVMF_VARS_TEMPLATE="${ovmf.variables}"
    echo "OVMF Secure Boot code: $OVMF_CODE"
    echo "Blank OVMF VARS template: $OVMF_VARS_TEMPLATE"
    echo "Run ./sb-lab init --pk PK.cer --kek KEK.cer --db DB.cer"
  '';
}
