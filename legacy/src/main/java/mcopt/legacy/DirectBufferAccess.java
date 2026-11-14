package mcopt.legacy;
public interface DirectBufferAccess {
    int meshnet$bufferId();
    int meshnet$terrainLayer();
    int meshnet$uploadRevision();
    void meshnet$markTerrain(int layer);
    void meshnet$vertexCount(int count);
}
