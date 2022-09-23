{.push raises:[Defect].}

import
  std/options,
  stew/results,
  bearssl,
  eth/keys,
  libp2p/crypto/crypto


type DosResult*[T] = Result[T, string]


proc randomPrivateKey*(): crypto.PrivateKey =
  crypto.PrivateKey.random(Secp256k1, keys.newRng()[]).get()
