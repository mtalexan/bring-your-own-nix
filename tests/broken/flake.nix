{
  description = "Intentionally invalid flake";
  outputs = _: throw "intentional test failure";
}
