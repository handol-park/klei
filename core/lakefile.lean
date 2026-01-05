import Lake
open Lake DSL

package core

lean_lib Klei

lean_exe core where
  root := `Main

lean_exe «test-socket» where
  root := `TestSocket

extern_lib libklei_socket pkg := do
  -- 1. Configuration common to all files
  let libFile := pkg.staticLibDir / "libklei_socket.a"
  let buildDir := pkg.buildDir / "FFI"
  let srcDir := pkg.dir / "FFI"
  let flags := #["-I", (← getLeanIncludeDir).toString, "-fPIC"]

  -- 2. Define the build recipe
  let buildObj (name : String) := do
    let oFile := buildDir / s!"{name}.o"
    let srcFile := srcDir / s!"{name}.c"
    let srcJob ← (inputTextFile srcFile)

    buildFileAfterDep oFile srcJob fun src => do
      compileO oFile src (moreArgs := flags) (compiler := "leanc")

  -- 3. Map the recipe over your files and build the lib
  -- Just add new filenames to this list!
  let oJobs ← #["socket", "lean_glue"].mapM buildObj

  -- 3. Use staticLibDir (nativeLibDir is deprecated)
  buildStaticLib libFile oJobs
