package mcopt.legacy.mixin;
import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.math.Matrix4f;
import java.nio.*;
import mcopt.legacy.*;
import org.lwjgl.opengl.GLCapabilities;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.*;
@Mixin(GlStateManager.class)
public abstract class DirectStateMixin {
    @Inject(method = "_pushLightingAttributes()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct0(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.pushLighting();
        callback.cancel();
    }
    @Inject(method = "_pushTextureAttributes()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct1(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.pushTextures();
        callback.cancel();
    }
    @Inject(method = "_popAttributes()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct2(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.popAttributes();
        callback.cancel();
    }
    @Inject(method = "_disableAlphaTest()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct3(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.alphaTest(false);
        callback.cancel();
    }
    @Inject(method = "_enableAlphaTest()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct4(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.alphaTest(true);
        callback.cancel();
    }
    @Inject(method = "_alphaFunc(IF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct5(int i, float f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.alpha(i, f);
        callback.cancel();
    }
    @Inject(method = "_enableLighting()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct6(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.lighting(true);
        callback.cancel();
    }
    @Inject(method = "_disableLighting()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct7(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.lighting(false);
        callback.cancel();
    }
    @Inject(method = "_enableLight(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct8(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_enableColorMaterial()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct9(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_disableColorMaterial()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct10(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_colorMaterial(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct11(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_light(IILjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct12(int i, int j, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.light(i, j, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_lightModel(ILjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct13(int i, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.ambient(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_normal3f(FFF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct14(float f, float g, float h, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.normal(f, g, h);
        callback.cancel();
    }
    @Inject(method = "_disableDepthTest()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct15(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.depthTest(false);
        callback.cancel();
    }
    @Inject(method = "_enableDepthTest()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct16(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.depthTest(true);
        callback.cancel();
    }
    @Inject(method = "_depthFunc(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct17(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.depthFunc(i);
        callback.cancel();
    }
    @Inject(method = "_depthMask(Z)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct18(boolean bl, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.depthMask(bl);
        callback.cancel();
    }
    @Inject(method = "_disableBlend()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct19(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.blend(false);
        callback.cancel();
    }
    @Inject(method = "_enableBlend()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct20(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.blend(true);
        callback.cancel();
    }
    @Inject(method = "_blendFunc(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct21(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.blendFunc(i, j);
        callback.cancel();
    }
    @Inject(method = "_blendFuncSeparate(IIII)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct22(int i, int j, int k, int l, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.blendFunc(i, j, k, l);
        callback.cancel();
    }
    @Inject(method = "_blendColor(FFFF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct23(float f, float g, float h, float i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_blendEquation(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct24(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.blendEquation(i);
        callback.cancel();
    }
    @Inject(method = "_init_fbo(Lorg/lwjgl/opengl/GLCapabilities;)Ljava/lang/String;", at = @At("HEAD"),
            cancellable = true)
    private static void
    meshnet$direct25(GLCapabilities gLCapabilities, CallbackInfoReturnable<String> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue("direct Vulkan");
    }
    @Inject(method = "glGetProgrami(II)I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct26(int i, int j, CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectPrograms.programStatus(i, j));
    }
    @Inject(method = "glAttachShader(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct27(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.attach(i, j);
        callback.cancel();
    }
    @Inject(method = "glDeleteShader(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct28(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.deleteShader(i);
        callback.cancel();
    }
    @Inject(method = "glCreateShader(I)I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct29(int i, CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectPrograms.createShader(i));
    }
    @Inject(method = "glShaderSource(ILjava/lang/CharSequence;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct30(int i, CharSequence charSequence, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.source(i, charSequence);
        callback.cancel();
    }
    @Inject(method = "glCompileShader(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct31(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.compile(i);
        callback.cancel();
    }
    @Inject(method = "glGetShaderi(II)I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct32(int i, int j, CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectPrograms.shaderStatus(i, j));
    }
    @Inject(method = "_glUseProgram(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct33(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.use(i);
        callback.cancel();
    }
    @Inject(method = "glCreateProgram()I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct34(CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectPrograms.createProgram());
    }
    @Inject(method = "glDeleteProgram(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct35(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.deleteProgram(i);
        callback.cancel();
    }
    @Inject(method = "glLinkProgram(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct36(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.link(i);
        callback.cancel();
    }
    @Inject(method = "_glGetUniformLocation(ILjava/lang/CharSequence;)I", at = @At("HEAD"),
            cancellable = true)
    private static void
    meshnet$direct37(int i, CharSequence charSequence, CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectPrograms.uniform(i, charSequence));
    }
    @Inject(method = "_glUniform1(ILjava/nio/IntBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct38(int i, IntBuffer intBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, intBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniform1i(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct39(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformInt(i, j);
        callback.cancel();
    }
    @Inject(method = "_glUniform1(ILjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct40(int i, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniform2(ILjava/nio/IntBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct41(int i, IntBuffer intBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, intBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniform2(ILjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct42(int i, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniform3(ILjava/nio/IntBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct43(int i, IntBuffer intBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, intBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniform3(ILjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct44(int i, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniform4(ILjava/nio/IntBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct45(int i, IntBuffer intBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, intBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniform4(ILjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct46(int i, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniformMatrix2(IZLjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct47(int i, boolean bl, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniformMatrix3(IZLjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct48(int i, boolean bl, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_glUniformMatrix4(IZLjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct49(int i, boolean bl, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectPrograms.uniformValues(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_glGetAttribLocation(ILjava/lang/CharSequence;)I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct50(int i, CharSequence charSequence,
                                         CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(0);
    }
    @Inject(method = "_glGenBuffers()I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct51(CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectVulkan.id());
    }
    @Inject(method = "_glBindBuffer(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct52(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.bindBuffer(i, j);
        callback.cancel();
    }
    @Inject(method = "_glBufferData(ILjava/nio/ByteBuffer;I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct53(int i, ByteBuffer byteBuffer, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.uploadBuffer(i, byteBuffer, j);
        callback.cancel();
    }
    @Inject(method = "_glDeleteBuffers(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct54(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.deleteBuffer(i);
        callback.cancel();
    }
    @Inject(method = "_glCopyTexSubImage2D(IIIIIIII)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct55(int i, int j, int k, int l, int m, int n, int o, int p,
                                         CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_glBindFramebuffer(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct56(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.bindTarget(i, j);
        callback.cancel();
    }
    @Inject(method = "getFramebufferDepthTexture()I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct57(CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(0);
    }
    @Inject(method = "_glBlitFrameBuffer(IIIIIIIIII)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct58(int i, int j, int k, int l, int m, int n, int o, int p, int q, int r,
                                         CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.copyDepth();
        callback.cancel();
    }
    @Inject(method = "_glDeleteFramebuffers(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct59(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectNative.deleteTarget(i);
        callback.cancel();
    }
    @Inject(method = "glGenFramebuffers()I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct60(CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectVulkan.id());
    }
    @Inject(method = "glCheckFramebufferStatus(I)I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct61(int i, CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(36053);
    }
    @Inject(method = "_glFramebufferTexture2D(IIIII)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct62(int i, int j, int k, int l, int m, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.attach(i, j, k, l, m);
        callback.cancel();
    }
    @Inject(method = "getActiveTextureName()I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct63(CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectVulkan.boundTexture());
    }
    @Inject(method = "glActiveTexture(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct64(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.activeTexture(i);
        callback.cancel();
    }
    @Inject(method = "_glClientActiveTexture(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct65(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_glMultiTexCoord2f(IFF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct66(int i, float f, float g, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.coordinates(i, f, g);
        callback.cancel();
    }
    @Inject(method = "glBlendFuncSeparate(IIII)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct67(int i, int j, int k, int l, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.blendFunc(i, j, k, l);
        callback.cancel();
    }
    @Inject(method = "glGetShaderInfoLog(II)Ljava/lang/String;", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct68(int i, int j, CallbackInfoReturnable<String> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectPrograms.error(i));
    }
    @Inject(method = "glGetProgramInfoLog(II)Ljava/lang/String;", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct69(int i, int j, CallbackInfoReturnable<String> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectPrograms.error(i));
    }
    @Inject(method = "_enableFog()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct80(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.fog(true);
        callback.cancel();
    }
    @Inject(method = "_disableFog()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct81(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.fog(false);
        callback.cancel();
    }
    @Inject(method = "_fogMode(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct82(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.fogMode(i);
        callback.cancel();
    }
    @Inject(method = "_fogDensity(F)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct83(float f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.fogDensity(f);
        callback.cancel();
    }
    @Inject(method = "_fogStart(F)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct84(float f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.fogStart(f);
        callback.cancel();
    }
    @Inject(method = "_fogEnd(F)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct85(float f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.fogEnd(f);
        callback.cancel();
    }
    @Inject(method = "_fog(I[F)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct86(int i, float[] fs, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.fogColor(i, fs);
        callback.cancel();
    }
    @Inject(method = "_fogi(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct87(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_enableCull()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct88(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.cull(true);
        callback.cancel();
    }
    @Inject(method = "_disableCull()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct89(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.cull(false);
        callback.cancel();
    }
    @Inject(method = "_polygonMode(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct90(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_enablePolygonOffset()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct91(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.polygonOffset(true);
        callback.cancel();
    }
    @Inject(method = "_disablePolygonOffset()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct92(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.polygonOffset(false);
        callback.cancel();
    }
    @Inject(method = "_enableLineOffset()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct93(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_disableLineOffset()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct94(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_polygonOffset(FF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct95(float f, float g, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.polygonOffset(f, g);
        callback.cancel();
    }
    @Inject(method = "_enableColorLogicOp()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct96(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.logic(true);
        callback.cancel();
    }
    @Inject(method = "_disableColorLogicOp()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct97(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.logic(false);
        callback.cancel();
    }
    @Inject(method = "_logicOp(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct98(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.logicOperation(i);
        callback.cancel();
    }
    @Inject(method = "_enableTexGen(Lcom/mojang/blaze3d/platform/GlStateManager$TexGen;)V", at = @At("HEAD"),
            cancellable = true)
    private static void
    meshnet$direct99(GlStateManager.TexGen texGen, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.texGen(true);
        callback.cancel();
    }
    @Inject(method = "_disableTexGen(Lcom/mojang/blaze3d/platform/GlStateManager$TexGen;)V", at = @At("HEAD"),
            cancellable = true)
    private static void
    meshnet$direct100(GlStateManager.TexGen texGen, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.texGen(false);
        callback.cancel();
    }
    @Inject(method = "_texGenMode(Lcom/mojang/blaze3d/platform/GlStateManager$TexGen;I)V", at = @At("HEAD"),
            cancellable = true)
    private static void
    meshnet$direct101(GlStateManager.TexGen texGen, int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(
        method = "_texGenParam(Lcom/mojang/blaze3d/platform/GlStateManager$TexGen;ILjava/nio/FloatBuffer;)V",
        at = @At("HEAD"), cancellable = true)
    private static void
    meshnet$direct102(GlStateManager.TexGen texGen, int i, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_activeTexture(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct103(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.activeTexture(i);
        callback.cancel();
    }
    @Inject(method = "_enableTexture()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct104(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.texturing(true);
        callback.cancel();
    }
    @Inject(method = "_disableTexture()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct105(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.texturing(false);
        callback.cancel();
    }
    @Inject(method = "_texEnv(III)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct106(int i, int j, int k, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.texEnv(i, j, k);
        callback.cancel();
    }
    @Inject(method = "_texParameter(IIF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct107(int i, int j, float f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.texParameter(i, j, f);
        callback.cancel();
    }
    @Inject(method = "_texParameter(III)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct108(int i, int j, int k, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.texParameter(i, j, k);
        callback.cancel();
    }
    @Inject(method = "_getTexLevelParameter(III)I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct109(int i, int j, int k, CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(0);
    }
    @Inject(method = "_genTexture()I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct110(CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectVulkan.id());
    }
    @Inject(method = "_deleteTexture(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct111(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.deleteTexture(i);
        callback.cancel();
    }
    @Inject(method = "_bindTexture(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct112(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.bindTexture(i);
        callback.cancel();
    }
    @Inject(method = "_texImage2D(IIIIIIIILjava/nio/IntBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct113(int i, int j, int k, int l, int m, int n, int o, int p,
                                          IntBuffer intBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.image(i, j, k, l, m, n, o, p, intBuffer);
        callback.cancel();
    }
    @Inject(method = "_texSubImage2D(IIIIIIIIJ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct114(int i, int j, int k, int l, int m, int n, int o, int p, long q,
                                          CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.upload(i, j, k, l, m, n, o, p, q);
        callback.cancel();
    }
    @Inject(method = "_getTexImage(IIIIJ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct115(int i, int j, int k, int l, long m, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.readTexture(i, j, k, l, m);
        callback.cancel();
    }
    @Inject(method = "_shadeModel(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct116(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_enableRescaleNormal()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct117(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_disableRescaleNormal()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct118(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_viewport(IIII)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct119(int i, int j, int k, int l, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.viewport(i, j, k, l);
        callback.cancel();
    }
    @Inject(method = "_colorMask(ZZZZ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct120(boolean bl, boolean bl2, boolean bl3, boolean bl4,
                                          CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.colorMask(bl, bl2, bl3, bl4);
        callback.cancel();
    }
    @Inject(method = "_stencilFunc(III)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct121(int i, int j, int k, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_stencilMask(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct122(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_stencilOp(III)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct123(int i, int j, int k, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_clearDepth(D)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct124(double d, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.clearDepth(d);
        callback.cancel();
    }
    @Inject(method = "_clearColor(FFFF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct125(float f, float g, float h, float i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.clearColor(f, g, h, i);
        callback.cancel();
    }
    @Inject(method = "_clearStencil(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct126(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_clear(IZ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct127(int i, boolean bl, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.clear(i, bl);
        callback.cancel();
    }
    @Inject(method = "_matrixMode(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct128(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrixMode(i);
        callback.cancel();
    }
    @Inject(method = "_loadIdentity()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct129(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().reset();
        callback.cancel();
    }
    @Inject(method = "_pushMatrix()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct130(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().push();
        callback.cancel();
    }
    @Inject(method = "_popMatrix()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct131(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().pop();
        callback.cancel();
    }
    @Inject(method = "_getMatrix(ILjava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct132(int i, FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.getMatrix(i, floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_ortho(DDDDDD)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct133(double d, double e, double f, double g, double h, double i,
                                          CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().ortho(d, e, f, g, h, i);
        callback.cancel();
    }
    @Inject(method = "_rotatef(FFFF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct134(float f, float g, float h, float i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().rotate(f, g, h, i);
        callback.cancel();
    }
    @Inject(method = "_scalef(FFF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct135(float f, float g, float h, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().scale(f, g, h);
        callback.cancel();
    }
    @Inject(method = "_scaled(DDD)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct136(double d, double e, double f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().scale(d, e, f);
        callback.cancel();
    }
    @Inject(method = "_translatef(FFF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct137(float f, float g, float h, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().translate(f, g, h);
        callback.cancel();
    }
    @Inject(method = "_translated(DDD)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct138(double d, double e, double f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.matrix().translate(d, e, f);
        callback.cancel();
    }
    @Inject(method = "_multMatrix(Ljava/nio/FloatBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct139(FloatBuffer floatBuffer, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.multiply(floatBuffer);
        callback.cancel();
    }
    @Inject(method = "_multMatrix(Lcom/mojang/math/Matrix4f;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct140(Matrix4f matrix4f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.multiply(matrix4f);
        callback.cancel();
    }
    @Inject(method = "_color4f(FFFF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct141(float f, float g, float h, float i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.color(f, g, h, i);
        callback.cancel();
    }
    @Inject(method = "_clearCurrentColor()V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct142(CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.clearCurrentColor();
        callback.cancel();
    }
    @Inject(method = "_normalPointer(IIJ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct143(int i, int j, long l, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_texCoordPointer(IIIJ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct144(int i, int j, int k, long l, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_vertexPointer(IIIJ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct145(int i, int j, int k, long l, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_colorPointer(IIIJ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct146(int i, int j, int k, long l, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_vertexAttribPointer(IIIZIJ)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct147(int i, int j, int k, boolean bl, int l, long m,
                                          CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_enableClientState(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct148(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_disableClientState(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct149(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_enableVertexAttribArray(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct150(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_disableVertexAttribArray(I)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct151(int i, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_drawArrays(III)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct152(int i, int j, int k, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.draw(i, j, k);
        callback.cancel();
    }
    @Inject(method = "_lineWidth(F)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct153(float f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_pixelStore(II)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct154(int i, int j, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        DirectVulkan.pixelStore(i, j);
        callback.cancel();
    }
    @Inject(method = "_pixelTransfer(IF)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct155(int i, float f, CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_readPixels(IIIIIILjava/nio/ByteBuffer;)V", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct156(int i, int j, int k, int l, int m, int n, ByteBuffer byteBuffer,
                                          CallbackInfo callback) {
        if (!DirectVulkan.active())
            return;
        callback.cancel();
    }
    @Inject(method = "_getError()I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct157(CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(0);
    }
    @Inject(method = "_getString(I)Ljava/lang/String;", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct158(int i, CallbackInfoReturnable<String> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectVulkan.getString(i));
    }
    @Inject(method = "_getInteger(I)I", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct159(int i, CallbackInfoReturnable<Integer> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(DirectVulkan.getInteger(i));
    }
    @Inject(method = "supportsFramebufferBlit()Z", at = @At("HEAD"), cancellable = true)
    private static void meshnet$direct160(CallbackInfoReturnable<Boolean> callback) {
        if (!DirectVulkan.active())
            return;
        callback.setReturnValue(true);
    }
}
