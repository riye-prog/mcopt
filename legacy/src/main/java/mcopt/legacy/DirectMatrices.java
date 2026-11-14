package mcopt.legacy;

import java.util.ArrayDeque;
import java.util.Deque;

public final class DirectMatrices {
    private float[] value = identity();
    private final Deque<float[]> stack = new ArrayDeque<>();
    public static float[] identity() {
        float[] result = new float[16];
        result[0] = result[5] = result[10] = result[15] = 1;
        return result;
    }
    public float[] values() { return value; }
    public void reset() { value = identity(); }
    public void push() { stack.push(value.clone()); }
    public void pop() {
        if (stack.isEmpty())
            throw new IllegalStateException("matrix stack underflow");
        value = stack.pop();
    }
    public void multiply(float[] right) { value = product(value, right); }
    public static float[] product(float[] left, float[] right) {
        float[] result = new float[16];
        for (int c = 0; c < 4; c++)
            for (int r = 0; r < 4; r++)
                for (int k = 0; k < 4; k++)
                    result[c * 4 + r] += left[k * 4 + r] * right[c * 4 + k];
        return result;
    }
    public void translate(double x, double y, double z) {
        float[] m = identity();
        m[12] = (float)x;
        m[13] = (float)y;
        m[14] = (float)z;
        multiply(m);
    }
    public void scale(double x, double y, double z) {
        float[] m = identity();
        m[0] = (float)x;
        m[5] = (float)y;
        m[10] = (float)z;
        multiply(m);
    }
    public void rotate(float degrees, float x, float y, float z) {
        double length = Math.sqrt(x * x + y * y + z * z);
        if (length == 0)
            return;
        x /= length;
        y /= length;
        z /= length;
        float c = (float)Math.cos(Math.toRadians(degrees)), s = (float)Math.sin(Math.toRadians(degrees)),
              t = 1 - c;
        float[] m = identity();
        m[0] = x * x * t + c;
        m[1] = y * x * t + z * s;
        m[2] = z * x * t - y * s;
        m[4] = x * y * t - z * s;
        m[5] = y * y * t + c;
        m[6] = z * y * t + x * s;
        m[8] = x * z * t + y * s;
        m[9] = y * z * t - x * s;
        m[10] = z * z * t + c;
        multiply(m);
    }
    public void ortho(double left, double right, double bottom, double top, double near, double far) {
        float[] m = identity();
        m[0] = (float)(2 / (right - left));
        m[5] = (float)(2 / (top - bottom));
        m[10] = (float)(-2 / (far - near));
        m[12] = (float)(-(right + left) / (right - left));
        m[13] = (float)(-(top + bottom) / (top - bottom));
        m[14] = (float)(-(far + near) / (far - near));
        multiply(m);
    }
}
