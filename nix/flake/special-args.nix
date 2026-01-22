{
  inputs,
  homelabConstants,
}: let
  sshPublicKey = let
    envKey = builtins.getEnv "SSH_PUB_KEY";
  in
    if envKey != ""
    then envKey
    else "";
  microvmTargets = let
    envTargets = builtins.getEnv "MICROVM_TARGETS";
  in
    if envTargets == "" || envTargets == "all"
    then null
    else if envTargets == "none"
    then []
    else builtins.filter (name: name != "") (builtins.split " " envTargets);
 in {
  inherit inputs homelabConstants microvmTargets;
  homelabConfig = homelabConstants.host;
  inherit sshPublicKey;
  isCI = false;
}

