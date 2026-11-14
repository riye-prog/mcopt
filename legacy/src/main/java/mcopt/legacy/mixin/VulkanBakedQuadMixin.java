package mcopt.legacy.mixin;

import mcopt.legacy.DistantTerrain;
import net.minecraft.client.renderer.block.model.BakedQuad;
import net.minecraft.client.renderer.texture.TextureAtlasSprite;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(BakedQuad.class)
public interface VulkanBakedQuadMixin extends DistantTerrain.QuadTexture {
    @Override
    @Accessor("sprite")
    TextureAtlasSprite meshnet$sprite();
}
