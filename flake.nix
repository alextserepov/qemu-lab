{
  description = "x86_64 QEMU + Secure Boot OVMF lab (custom PK/KEK/db)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Importantly, the base OVMF default does NOT enable Secure Boot.
      # This produces Secure Boot-capable x86_64 OVMF + a blank VARS template.
      ovmf = pkgs.OVMF.override {
        secureBoot = true;
        fdSize4MB = true;
        msVarsTemplate = false;
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
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
      };
    };
}
