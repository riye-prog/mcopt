import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

def align(value,boundary):
 return (value+boundary-1)//boundary*boundary

def compile_effects(minecraft,compiler,output,vulkan=False):
 archive=zipfile.ZipFile(minecraft)
 prefix='assets/minecraft/shaders/program/'
 shaders={name[len(prefix):]:archive.read(name).decode() for name in archive.namelist() if name.startswith(prefix) and name.endswith(('.vsh','.fsh'))}
 pairs=sorted(set((json.loads(archive.read(name))['vertex'],json.loads(archive.read(name))['fragment']) for name in archive.namelist() if name.startswith(prefix) and name.endswith('.json')))
 if not vulkan:
  lib=ctypes.CDLL(str(compiler))
  translate=lib.meshnet_translate if hasattr(lib,'meshnet_translate') else lib.tin_translate
  release=lib.meshnet_free if hasattr(lib,'meshnet_free') else lib.tin_free
  translate.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_char_p]
  translate.restype=ctypes.c_void_p
  release.argtypes=[ctypes.c_void_p]
 output.mkdir(parents=True,exist_ok=True)
 manifest={'shaders':{name:hashlib.sha256(text.encode()).hexdigest() for name,text in shaders.items()},'programs':{}}
 for vertex,fragment in pairs:
  sources=[shaders[vertex+'.vsh'],shaders[fragment+'.fsh']]
  fields={}
  samplers=[]
  for source in sources:
   for kind,name in re.findall(r'uniform\s+(\w+)\s+(\w+)\s*;',source):
    if kind.startswith('sampler'):
     if name not in samplers:samplers.append(name)
    else:fields[name]=kind
  fields=dict(sorted(fields.items()))
  offset=0
  uniforms={}
  for name,kind in fields.items():
   count={'float':1,'vec2':2,'vec3':3,'vec4':4,'mat4':16,'int':1}[kind]
   offset=align(offset,4 if count==1 else 8 if count==2 else 16)
   uniforms[name]={'offset':offset,'count':count,'type':kind}
   offset+=count*4
  block='layout(std140,binding=0) uniform EffectUniforms {\n'+''.join(kind+' '+name+';\n' for name,kind in fields.items())+'};\n'
  binaries=[]
  with tempfile.TemporaryDirectory(prefix='meshnet-shaders-') as directory:
   for stage,source in zip(['vert','frag'],sources):
    source=re.sub(r'^#version.*$','',source,flags=re.M)
    source=re.sub(r'uniform\s+(?!sampler)\w+\s+\w+\s*;','',source)
    source=re.sub(r'uniform\s+(sampler\w+)\s+(\w+)\s*;',lambda m:'layout(binding='+str(samplers.index(m[2])+(2 if vulkan else 0))+') uniform '+m[1]+' '+m[2]+';',source)
    source=re.sub(r'\battribute\b','in',source)
    source=re.sub(r'\bvarying\b','out' if stage=='vert' else 'in',source)
    source=re.sub(r'\btexture2D\s*\(', 'texture(',source)
    if stage=='frag':source='layout(location=0) out vec4 meshnetColor;\n'+source.replace('gl_FragColor','meshnetColor')
    if vulkan and stage=='vert':
     source=re.sub(r'(gl_Position\s*=\s*[^;]+;)',r'\1 gl_Position.y = -gl_Position.y; gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;',source)
    source='#version 450\n'+block+source
    path=Path(directory)/('effect.'+stage)
    path.write_text(source)
    result=subprocess.run(['glslangValidator','-V','--auto-map-locations',str(path),'-o',str(path)+'.spv'],capture_output=True,text=True)
    if result.returncode:raise RuntimeError(vertex+'/'+fragment+' '+result.stdout+result.stderr)
    binaries.append(Path(str(path)+'.spv').read_bytes())
   if vulkan:
    name=vertex+'__'+fragment
    for stage,binary in zip(['vert','frag'],binaries):
     (output/(name+'.'+stage+'.spv')).write_bytes(binary)
    manifest['programs'][name]={'fields':uniforms,'size':align(offset,16),'textures':[{'name':sampler,'index':i} for i,sampler in enumerate(samplers)]}
    continue
   request=json.dumps({'inputs':['Position'],'buffers':1,'texels':[],'uniforms':['EffectUniforms'],'samplers':samplers,'pushConstants':0}).encode()
   ptr=translate(binaries[0],len(binaries[0]),binaries[1],len(binaries[1]),request)
   result=json.loads(ctypes.string_at(ptr));release(ptr)
  if result.get('error'):raise RuntimeError(vertex+'/'+fragment+': '+result['error'])
  result['vertex']=result['vertex'].replace('return out;','out.gl_Position.z = (out.gl_Position.z + out.gl_Position.w) * 0.5;\n    return out;')
  result['vertex']=re.sub(r'//[^\n]*','',result['vertex'])
  result['fragment']=re.sub(r'//[^\n]*','',result['fragment'])
  name=vertex+'__'+fragment
  (output/(name+'.vert.metal')).write_text(result.pop('vertex'))
  (output/(name+'.frag.metal')).write_text(result.pop('fragment'))
  result['fields']=uniforms
  result['size']=align(offset,16)
  manifest['programs'][name]=result
 (output/'effects.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print('compiled',len(pairs),'stock shader programs to', 'SPIR-V' if vulkan else 'Metal')

if __name__=='__main__':
 parser=argparse.ArgumentParser()
 parser.add_argument('minecraft',type=Path)
 parser.add_argument('compiler',type=Path)
 parser.add_argument('output',type=Path)
 parser.add_argument('--vulkan',action='store_true')
 args=parser.parse_args()
 compile_effects(args.minecraft,args.compiler,args.output,args.vulkan)
