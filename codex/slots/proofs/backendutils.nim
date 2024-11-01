import ./backends

type
  BackendUtils* = ref object of RootObj

method initializeCircomBackend*(
  self: BackendUtils,
  r1csFile: string,
  wasmFile: string,
  zKeyFile: string
): AnyBackend {.base.} =
  CircomCompat.init(r1csFile, wasmFile, zKeyFile)