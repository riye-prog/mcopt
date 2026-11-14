import argparse
from pathlib import Path
import struct
import subprocess
import tempfile


def compile_shaders(source, header):
    header.parent.mkdir(parents=True, exist_ok=True)
    declarations = []
    with tempfile.TemporaryDirectory(prefix="meshnet-vulkan-") as directory:
        for shader in sorted(source.iterdir()):
            binary = Path(directory) / (shader.name + ".spv")
            subprocess.run(["glslangValidator", "-V", str(shader), "-o", str(binary)], check=True)
            words = [str(word[0]) for word in struct.iter_unpack("<I", binary.read_bytes())]
            name = shader.name.replace(".", "_")
            declaration = f"static const uint32_t {name}[] = {{\n"
            declaration += "".join("    " + ", ".join(words[i:i + 12]) + ",\n" for i in range(0, len(words), 12))
            declarations.append(declaration + "};\n")
    header.write_text("#pragma once\n#include <cstdint>\n" + "\n".join(declarations))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("shaders", type=Path)
    parser.add_argument("header", type=Path)
    args = parser.parse_args()
    compile_shaders(args.shaders, args.header)
