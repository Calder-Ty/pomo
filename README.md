# pomo

## A Pomodoro Timer

### Usage

#### Executable

- Build from source:

```sh
git clone https://github.com/calder-ty/pomo.git
cd pomo/
zig build exe -- -h
```

- Download latest release:

```sh
wget https://github.com/calder-ty/pomo/releases/latest/download/<archive>
tar -xf <archive> # Unix
unzip <archive> # Windows
./<binary> -h
```

#### Module

1. Add `pomo` dependency to `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/calder-ty/pomo.git
```

2. Use `pomo` dependency in `build.zig`:

```zig
const pomo_dep = b.dependency("pomo", .{
    .target = target,
    .optimize = optimize,
});
const pomo_mod = pomo_dep.module("pomo");
<std.Build.Step.Compile>.root_module.addImport("pomo", pomo_mod);
```
