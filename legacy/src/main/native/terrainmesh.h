#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace terrainmesh {
using Vertex = std::array<uint32_t, 8>;
using Quad = std::array<Vertex, 4>;
constexpr int stride = sizeof(Vertex);
constexpr int grid = 16;
constexpr int planeSize = grid * grid;
constexpr int faceSize = (grid + 1) * planeSize;
constexpr int faceCount = 7;

inline float asFloat(uint32_t word) {
    float value;
    std::memcpy(&value, &word, sizeof(value));
    return value;
}

inline uint32_t asWord(float value) {
    uint32_t word;
    std::memcpy(&word, &value, sizeof(word));
    return word;
}

struct Group {
    uint32_t first = 0;
    uint32_t count = 0;
    float minPlane = 0;
    float maxPlane = 0;
};

struct Candidate {
    int32_t quad = 0;
    uint8_t corners = 0;
    uint8_t uvCorners = 0;
};

struct Result {
    std::array<Group, faceCount> groups{};
    uint32_t vertices = 0;
    uint32_t saved = 0;
};

struct Builder {
    std::vector<Quad> input;
    std::vector<Quad> output;
    std::vector<uint8_t> faces;
    std::vector<bool> removed;
    std::vector<int> cellsUsed;
    std::array<Candidate, 6 * faceSize> cells{};
    std::array<std::vector<Quad>, 6> merged;

    Result build(const void *source, size_t size, bool greedy, bool separateFaces) {
        size_t quads = size / sizeof(Quad);
        input.resize(quads);
        std::memcpy(input.data(), source, quads * sizeof(Quad));
        output.clear();
        output.reserve(quads);
        faces.assign(quads, 6);
        removed.assign(quads, false);
        for (auto &group : merged) group.clear();
        for (size_t i = 0; i < quads; i++) {
            Quad &quad = input[i];
            for (Vertex &vertex : quad) vertex[7] = 0;
            if (!separateFaces) continue;
            int face = facing(quad);
            faces[i] = face;
            if (greedy && face < 6) identify(quad, face, i);
        }
        if (!cellsUsed.empty()) {
            std::sort(cellsUsed.begin(), cellsUsed.end());
            for (int key : cellsUsed) merge(key);
            for (int key : cellsUsed) cells[key] = {};
            cellsUsed.clear();
        }
        Result result;
        for (int face = 0; face < faceCount; face++) {
            Group &range = result.groups[face];
            range.first = output.size() * 4;
            auto append = [&](const Quad &quad) {
                if (face < 6) {
                    float plane = asFloat(quad[0][face / 2]);
                    if (range.count == 0) range.minPlane = range.maxPlane = plane;
                    else {
                        range.minPlane = std::min(range.minPlane, plane);
                        range.maxPlane = std::max(range.maxPlane, plane);
                    }
                }
                output.push_back(quad);
                range.count += 4;
            };
            for (size_t i = 0; i < quads; i++) {
                if (faces[i] == face && !removed[i]) append(input[i]);
            }
            if (face < 6) for (const Quad &quad : merged[face]) append(quad);
        }
        result.vertices = output.size() * 4;
        result.saved = quads * 4 - result.vertices;
        return result;
    }

    static int facing(const Quad &quad) {
        for (int axis = 0; axis < 3; axis++) {
            uint32_t plane = quad[0][axis];
            if (quad[1][axis] != plane || quad[2][axis] != plane || quad[3][axis] != plane) continue;
            int a = (axis + 1) % 3;
            int b = (axis + 2) % 3;
            auto delta = [&](int vertex, int other, int component) {
                return asFloat(quad[vertex][component]) - asFloat(quad[other][component]);
            };
            float first = delta(1, 0, a) * delta(2, 0, b) - delta(1, 0, b) * delta(2, 0, a);
            float second = delta(3, 2, a) * delta(0, 2, b) - delta(3, 2, b) * delta(0, 2, a);
            if (first > 0 && second > 0) return axis * 2 + 1;
            if (first < 0 && second < 0) return axis * 2;
        }
        return 6;
    }

    static bool winding(uint8_t order) {
        unsigned seen = 0;
        for (int i = 0; i < 4; i++) {
            unsigned corner = (order >> (i * 2)) & 3;
            unsigned next = (order >> (((i + 1) & 3) * 2)) & 3;
            unsigned edge = corner ^ next;
            if ((seen & (1u << corner)) || (edge != 1 && edge != 2)) return false;
            seen |= 1u << corner;
        }
        return true;
    }

    void identify(const Quad &quad, int face, size_t index) {
        int axis = face / 2;
        int a = (axis + 1) % 3;
        int b = (axis + 2) % 3;
        float plane = asFloat(quad[0][axis]);
        if (!(plane >= 0 && plane <= grid && plane == std::floor(plane))) return;
        float minA = grid, minB = grid, maxA = 0, maxB = 0;
        float minU = 1, minV = 1, maxU = 0, maxV = 0;
        for (const auto &vertex : quad) {
            float pa = asFloat(vertex[a]), pb = asFloat(vertex[b]);
            if (!(pa >= 0 && pa <= grid && pb >= 0 && pb <= grid)) return;
            minA = std::min(minA, pa);
            minB = std::min(minB, pb);
            maxA = std::max(maxA, pa);
            maxB = std::max(maxB, pb);
        }
        if (maxA - minA != 1 || maxB - minB != 1 || minA != std::floor(minA) || minB != std::floor(minB)) return;
        uint8_t corners = 0;
        for (int i = 0; i < 4; i++) {
            float pa = asFloat(quad[i][a]), pb = asFloat(quad[i][b]);
            if ((pa != minA && pa != maxA) || (pb != minB && pb != maxB)) return;
            corners |= ((pa == maxA ? 1 : 0) | (pb == maxB ? 2 : 0)) << (i * 2);
        }
        if (!winding(corners)) return;
        int key = face * faceSize + int(plane) * planeSize + int(minB) * grid + int(minA);
        Candidate &cell = cells[key];
        if (cell.quad) {
            cell.quad = -1;
            return;
        }
        cellsUsed.push_back(key);
        cell.quad = -1;
        for (const auto &vertex : quad) {
            if (vertex[3] != quad[0][3] || vertex[6] != quad[0][6]) return;
            float u = asFloat(vertex[4]), v = asFloat(vertex[5]);
            if (!(u >= 0 && u <= 1 && v >= 0 && v <= 1)) return;
            minU = std::min(minU, u);
            minV = std::min(minV, v);
            maxU = std::max(maxU, u);
            maxV = std::max(maxV, v);
        }
        if (atlas(minU, minV) == atlas(maxU, minV) || atlas(minU, minV) == atlas(minU, maxV)) return;
        uint8_t uvCorners = 0;
        for (int i = 0; i < 4; i++) {
            float u = asFloat(quad[i][4]), v = asFloat(quad[i][5]);
            if ((u != minU && u != maxU) || (v != minV && v != maxV)) return;
            uvCorners |= ((u == maxU ? 1 : 0) | (v == maxV ? 2 : 0)) << (i * 2);
        }
        if (!winding(uvCorners)) return;
        cell = {static_cast<int32_t>(index + 1), corners, uvCorners};
    }

    static uint32_t atlas(float u, float v) {
        return uint32_t(std::lround(u * 65535)) | (uint32_t(std::lround(v * 65535)) << 16);
    }

    bool matches(const Candidate &first, int key) const {
        const Candidate &other = cells[key];
        if (other.quad <= 0 || other.corners != first.corners || other.uvCorners != first.uvCorners) return false;
        const Quad &left = input[first.quad - 1];
        const Quad &right = input[other.quad - 1];
        if (left[0][3] != right[0][3] || left[0][6] != right[0][6]) return false;
        for (int i = 0; i < 4; i++) {
            if (left[i][4] != right[i][4] || left[i][5] != right[i][5]) return false;
        }
        return true;
    }

    void merge(int key) {
        Candidate start = cells[key];
        if (start.quad <= 0) return;
        int minA = key % grid;
        int minB = (key % planeSize) / grid;
        int width = 1;
        while (minA + width < grid && matches(start, key + width)) width++;
        int height = 1;
        while (minB + height < grid) {
            int column = 0;
            while (column < width && matches(start, key + height * grid + column)) column++;
            if (column != width) break;
            height++;
        }
        if (width * height < 2) return;
        Quad rectangle = input[start.quad - 1];
        unsigned firstCorner = start.corners & 3;
        unsigned firstUv = start.uvCorners & 3;
        bool uAlongA = false;
        float minU = 1, minV = 1, maxU = 0, maxV = 0;
        for (int i = 0; i < 4; i++) {
            unsigned corner = (start.corners >> (2 * i)) & 3;
            unsigned uvCorner = (start.uvCorners >> (2 * i)) & 3;
            if ((corner ^ firstCorner) == 1) uAlongA = ((uvCorner ^ firstUv) & 1) != 0;
            float u = asFloat(rectangle[i][4]), v = asFloat(rectangle[i][5]);
            minU = std::min(minU, u);
            minV = std::min(minV, v);
            maxU = std::max(maxU, u);
            maxV = std::max(maxV, v);
        }
        int face = key / faceSize;
        int axis = face / 2;
        for (int i = 0; i < 4; i++) {
            unsigned corner = (start.corners >> (2 * i)) & 3;
            unsigned uvCorner = (start.uvCorners >> (2 * i)) & 3;
            Vertex &vertex = rectangle[i];
            vertex[(axis + 1) % 3] = asWord(minA + ((corner & 1) ? width : 0));
            vertex[(axis + 2) % 3] = asWord(minB + ((corner & 2) ? height : 0));
            vertex[4] = atlas(minU, minV);
            vertex[5] = atlas(maxU, maxV);
            vertex[7] = 0x10000u | ((uvCorner & 1) ? (uAlongA ? width : height) : 0)
                | (((uvCorner & 2) ? (uAlongA ? height : width) : 0) << 8);
        }
        merged[face].push_back(rectangle);
        for (int row = 0; row < height; row++) {
            for (int col = 0; col < width; col++) {
                Candidate &cell = cells[key + row * grid + col];
                removed[cell.quad - 1] = true;
                cell.quad = -1;
            }
        }
    }
};
}
