
using Tar, Inflate, SHA, Downloads

@assert length(ARGS) == 1 "Expected link to artifact resource as argument"
link = ARGS[1]

path = Downloads.download(link)
println("sha256: ", bytes2hex(open(sha256, path)))
println("git-tree-sha1: ", Tar.tree_hash(IOBuffer(inflate_gzip(path))))
