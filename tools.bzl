load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_go//go:def.bzl", "go_context")

def _go_sdk_tool_impl(ctx):
    # Locate the File object corresponding to the tool path. This is needed for
    # bazel to be able to create an executable symlink to that tool and to be
    # able to recreate the symlink if the tool changes.
    go = go_context(ctx)
    sdk = go.sdk
    tool_path = paths.join(sdk.root_file.dirname, ctx.attr.goroot_relative_path)
    tool = None

    sdk_tools = [sdk.go]  # `go` binary
    sdk_tools.extend(sdk.tools.to_list())  # all other tools, e.g. `gofmt`

    for f in sdk_tools:
        if f.path == tool_path:
            tool = f
            break
    if not tool:
        fail("could not locate SDK tool '%s'" % tool_path)

    # Declare an executable symlink to the tool File.
    tool_symlink = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.symlink(output = tool_symlink, target_file = tool, is_executable = True)

    # Declare a launcher script that changes to the current
    # directory before running, since `bazel run` executes
    # the tool under the build runfiles dir by default.
    launcher_script = ctx.actions.declare_file(ctx.attr.name + "_launcher.sh")
    ctx.actions.write(
        launcher_script,
        """#!/usr/bin/env bash
        set -eu
        TOOL_PATH="$(readlink ./%s)"
        cd "$BUILD_WORKING_DIRECTORY"
        exec "$TOOL_PATH" "$@"
        """ % ctx.attr.name,
        is_executable = True,
    )

    return [DefaultInfo(
        files = depset([tool_symlink, launcher_script]),
        runfiles = ctx.runfiles(files = [tool_symlink]),
        executable = launcher_script,
    )]

# copied from buildbuddy: https://github.com/buildbuddy-io/buildbuddy/blob/master/rules/go/index.bzl
go_sdk_tool = rule(
    doc = "Declares a run target from the go SDK.",
    attrs = {
        "goroot_relative_path": attr.string(mandatory = True, doc = "Tool path relative to the go SDK root (GOROOT)"),
        "_go_context_data": attr.label(
            default = "@rules_go//:go_context_data",
        ),
    },
    implementation = _go_sdk_tool_impl,
    executable = True,
    toolchains = ["@rules_go//go:toolchain"],
)

def _go_fmt_test_impl(ctx):
    srcs = ctx.files.srcs

    content = "{driver} fmt {srcs}".format(
        srcs = " ".join([f.path for f in srcs]),
        driver = ctx.executable._driver.short_path,
    )

    executable = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.write(executable, content = content, is_executable = True)

    files = [
        ctx.executable._driver,
    ] + srcs

    return [
        DefaultInfo(
            executable = executable,
            runfiles = ctx.runfiles(
                files = files,
            ),
        ),
    ]

go_fmt_test = rule(
    attrs = {
        "srcs": attr.label_list(
            allow_empty = False,
            allow_files = [".go"],
            doc = "Source files to format",
            mandatory = True,
        ),
        "_driver": attr.label(
            cfg = "host",
            #default = "//:go_sh",
	        default = ":gofmt",
            executable = True,
        ),
    },
    doc = "Test formatting of go files, fail if there is an error",
    test = True,
    implementation = _go_fmt_test_impl,
)



def create_lib(name, srcs):
    go_fmt_test(
        name = "%s-fmt-test" % name,
        srcs = srcs)
