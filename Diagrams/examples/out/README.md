Generated files. Each must match a fresh run byte for byte (checked by `tests/test_cli.py`):

    python -B -m diagram_tool examples/raw/smoke.json -o examples/out/smoke.drawio
    python -B -m diagram_tool examples/erd/erd_demo.meta.json -o examples/out/      (-> erd_demo.gen.drawio)

Do not edit by hand; change the JSON source (`examples/raw/smoke.json`, `examples/erd/erd_demo.meta.json`)
and regenerate. `erd_demo` is made-up data, not a real project.
