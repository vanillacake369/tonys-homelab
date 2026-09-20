{
  assert',
  collected,
}: [
  (assert' "overlays: finds overlay files" (builtins.length collected > 0))
  (assert' "overlays: all are functions" (builtins.all builtins.isFunction collected))
  (assert' "overlays: expected count" (builtins.length collected == 3))
]
