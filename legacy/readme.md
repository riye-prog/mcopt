# meshnet vulkan for minecraft 1.16.1

put the jar in a minecraft 1.16.1 fabric instance on apple silicon. use an arm64 java runtime with arm64 lwjgl natives and disable sodium, sodium mac, and other meshnet renderer jars for this instance.

the mod creates a window without an opengl context. terrain, water, entities, the hud, and stock post effects use vulkan. moltenvk ships inside the jar and runs those vulkan commands on the mac gpu.

the fast profile is on by default. it uses greedy terrain meshes for the nearest 8 chunks in the overworld. beyond that it uses textured terrain with a finer lod near the transition, tree silhouettes, and biome-tinted water. set `-Dmeshnet.vulkan.detailDistance=12` for a wider full-detail radius or `-Dmeshnet.vulkan.fast=false` for full-detail terrain at the selected distance. greedy meshing stays enabled in both profiles.

to build locally, use java 25, xcode command line tools, python 3, glslangvalidator, vulkan headers, and moltenvk's static library. run `./gradlew :legacy:build`. the jar lands in `legacy/build/libs`.

a mod that expects a live opengl context needs its own integration. the older benchmark json files report the earlier metal renderer.
