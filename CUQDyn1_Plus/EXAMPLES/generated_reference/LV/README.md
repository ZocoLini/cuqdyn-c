# LV Generated Reference Snapshot

This folder keeps a small, committed text snapshot of the files produced by
`cuqdyn_generate_problem_files` for `EXAMPLES/LV/define_problem_LV.m`.

The high-level `define_problem_*.m` files are the source of truth. Per-example
`generated_problem/` folders are disposable local outputs and are ignored by
Git. Regenerate them when needed with `cuqdyn_generate_problem_files`.

The snapshots use the `.m.txt` suffix so broad MATLAB `genpath` calls do not
accidentally put duplicate callable `prob_mod_*_LV` functions on the path.
