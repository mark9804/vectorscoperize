#include <metal_stdlib>
using namespace metal;

// NTSC constants
constant float a_r = 0.701;
constant float b_r = -0.587;
constant float c_r = -0.114;

constant float a_b = -0.299;
constant float b_b = -0.587;
constant float c_b = 0.886;

// --- Helpers ---

bool is_on_line(float2 pos, float2 start, float2 end, float thickness) {
    float2 dir = end - start;
    float len = length(dir);
    if (len == 0.0) return false;
    dir /= len;
    float2 to_pos = pos - start;
    float proj = dot(to_pos, dir);
    if (proj < 0.0 || proj > len) return false;
    float2 perp = to_pos - dir * proj;
    return length(perp) < thickness / 2.0;
}

bool is_on_circle(float2 pos, float2 center, float radius, float thickness) {
    float r = distance(pos, center);
    return abs(r - radius) < thickness / 2.0;
}

bool is_in_box(float2 pos, float2 box_center, float box_size, float thickness) {
    float2 d = abs(pos - box_center);
    bool inside = (d.x < box_size && d.y < box_size);
    bool border = (d.x > box_size - thickness && d.x < box_size) || (d.y > box_size - thickness && d.y < box_size);
    return inside && border;
}

// --- Background Kernels ---

// Configuration Struct matching Swift
struct GraticuleConfig {
    float2 targetR;
    float2 targetMG;
    float2 targetB;
    float2 targetCY;
    float2 targetG;
    float2 targetYL;
    
    float skinAngle;
    float skinSat;
    float boxSizeRatio;
    float padding;
};

// Generic Clear (Black)
kernel void clear_texture(texture2d<float, access::write> outTexture [[texture(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
    outTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
}

// Vector Scope Background with Configurable Targets
kernel void clear_vector(texture2d<float, access::write> outTexture [[texture(0)]],
                         constant GraticuleConfig &config [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
    
    float width = float(outTexture.get_width());
    float height = float(outTexture.get_height());
    float2 center = float2(width * 0.5, height * 0.5);
    float2 pos = float2(gid);
    
    // 1. Base color
    float4 color = float4(0.02, 0.02, 0.02, 1.0); 
    
    float2 delta = pos - center;
    float dist = length(delta);
    float radius = min(width, height) * 0.45; // Represents 100% excursion
    
    // 2. Crosshair (Grey)
    if (abs(delta.x) < 0.5 || abs(delta.y) < 0.5) {
        color = float4(0.25, 0.25, 0.25, 1.0);
    }
    
    // 3. Circles
    // 25% Circle
    if (is_on_circle(pos, center, radius * 0.25, 1.0)) {
        color += float4(0.15, 0.15, 0.15, 0.0);
    }
    // 50% Circle
    if (is_on_circle(pos, center, radius * 0.50, 1.0)) {
        color += float4(0.15, 0.15, 0.15, 0.0);
    }
    // 75% Circle (Faint)
    if (is_on_circle(pos, center, radius * 0.75, 1.0)) {
        color += float4(0.15, 0.15, 0.15, 0.0);
    }
    // 100% Circle (Bit brighter)
    if (is_on_circle(pos, center, radius, 1.0)) {
        color += float4(0.2, 0.2, 0.2, 0.0);
    }
    
    // 4. Color Targets (From Config)
    
    // 4. Color Targets (From Config)
    
    float box_half_size = width * config.boxSizeRatio; 
    
    // Array access in metal from struct fields is manual or copy to array
    float2 targets[6];
    targets[0] = config.targetR;
    targets[1] = config.targetMG;
    targets[2] = config.targetB;
    targets[3] = config.targetCY;
    targets[4] = config.targetG;
    targets[5] = config.targetYL;
    
    for (int i = 0; i < 6; i++) {
        // Position scaled by radius (which is 100% magnitude reference)
        // Targets are now pre-scaled to 75% magnitude in config
        float2 t_pos = center + targets[i] * radius; 
        
        // Draw Outer Box
        if (is_in_box(pos, t_pos, box_half_size, 1.0)) {
            color = float4(0.6, 0.6, 0.6, 1.0);
        }
        // Draw Inner Box
         if (is_in_box(pos, t_pos, box_half_size * 0.2, 1.0)) {
            color = float4(0.9, 0.9, 0.9, 1.0);
        }
    }
    
    // 5. Skin Tone Line (I-Axis)
    float skin_angle_rad = config.skinAngle * 3.14159 / 180.0;
    float2 skin_dir = float2(cos(skin_angle_rad), -sin(skin_angle_rad));
    
    // Draw from center to edge
    if (is_on_line(pos, center, center + skin_dir * radius, 1.0)) {
        color = float4(0.7, 0.5, 0.3, 1.0); // Orange-ish
    }
    
    // Skin Tone Box
    float sat_skin = config.skinSat;
    float2 skin_pos = center + skin_dir * radius * sat_skin;
    if (is_in_box(pos, skin_pos, box_half_size, 1.0)) {
         color = float4(0.8, 0.6, 0.4, 1.0); 
    }
    if (is_in_box(pos, skin_pos, box_half_size * 0.2, 1.0)) {
         color = float4(1.0, 1.0, 1.0, 1.0);
    }
    
    // Q-Axis (90 deg from I)
    float q_angle = skin_angle_rad - (90.0 * 3.14159 / 180.0); 
    float2 q_dir = float2(cos(q_angle), -sin(q_angle));
    // Draw full line through center
    if (is_on_line(pos, center - q_dir * radius, center + q_dir * radius, 1.0)) {
        color += float4(0.4, 0.0, 0.6, 0.4); // Purple-ish
    }

    outTexture.write(color, gid);
}

// RGB Parade Background with Grid
kernel void clear_parade(texture2d<float, access::write> outTexture [[texture(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
    
    float width = float(outTexture.get_width());
    float height = float(outTexture.get_height());
    float2 pos = float2(gid);
    
    float4 color = float4(0.02, 0.02, 0.02, 1.0);
    
    float sectionH = height / 3.0;
    
    // Draw section dividers
    if (abs(pos.y - sectionH) < 1.0 || abs(pos.y - sectionH * 2.0) < 1.0) {
        color = float4(0.5, 0.5, 0.5, 1.0);
    }
    
    // Detailed Grids: 0, 25, 50, 75, 100%
    float localY = fmod(pos.y, sectionH);
    
    bool is_grid = false;
    if (abs(localY - sectionH * 0.25) < 0.5) is_grid = true; // 75%
    if (abs(localY - sectionH * 0.50) < 0.5) is_grid = true; // 50%
    if (abs(localY - sectionH * 0.75) < 0.5) is_grid = true; // 25%
    
    if (is_grid) {
        color += float4(0.15, 0.15, 0.15, 0.0);
    }

    outTexture.write(color, gid);
}

// --- Accumulation Kernels ---

// Vector Scope Accessor
kernel void vectorscope_accumulate(texture2d<float, access::read> inTexture [[texture(0)]],
                                   texture2d<float, access::read_write> outTexture [[texture(1)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;

    float4 color = inTexture.read(gid);
    float r = color.r;
    float g = color.g;
    float b = color.b;

    // Calculate Ry, By
    float ry = a_r * r + b_r * g + c_r * b;
    float by = a_b * r + b_b * g + c_b * b;
    
    // NTSC Scaling Factors
    // B-Y (U) scale: 0.493. R-Y (V) scale: 0.877.
    // We norm to [-0.5, 0.5] range effectively (or rather, just scale correctly).
    // The divisor should be the inverse of the scale factor?
    // U = 0.493 * (B-Y). 
    // We want to PLOT U. So norm_x = U.
    // norm_x = 0.493 * by.
    // Wait, previous code was `by / 2.03`. 2.03 is approx 1/0.493.
    // So `by * 0.493` is the same as `by / 2.028...`.
    // Let's use the precise multiply.
    
    float norm_x = by * 0.493;
    float norm_y = -(ry * 0.877); // Negative for Y-flip
 
    float width = float(outTexture.get_width());
    float height = float(outTexture.get_height());
    float radius = min(width, height) * 0.45; 
    
    float2 center = float2(width * 0.5, height * 0.5);
    float2 pos = center + float2(norm_x, norm_y) * radius;
    uint2 targetPos = uint2(pos);
    
    if (targetPos.x < uint(width) && targetPos.y < uint(height)) {
        float4 current = outTexture.read(targetPos);
        float intensity = 0.8; // Increased slightly from 0.5 to maintain brightness with colored pixels
        float3 traceColor = color.rgb * intensity;
        current.rgb += traceColor;
        outTexture.write(min(current, float4(4.0)), targetPos); 
    }
}

// RGB Parade Accessor
kernel void rgb_parade_accumulate(texture2d<float, access::read> inTexture [[texture(0)]],
                                  texture2d<float, access::read_write> outTexture [[texture(1)]],
                                  uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;

    float4 color = inTexture.read(gid);
    
    uint outWidth = outTexture.get_width();
    uint outHeight = outTexture.get_height();
    uint sectionHeight = outHeight / 3;
    
    uint targetX = (uint)((float(gid.x) / float(inTexture.get_width())) * float(outWidth));
    
    float rVal = 1.0 - color.r;
    float gVal = 1.0 - color.g;
    float bVal = 1.0 - color.b;

    uint rY = (uint)(rVal * float(sectionHeight - 1));
    uint gY = (uint)(gVal * float(sectionHeight - 1)) + sectionHeight;
    uint bY = (uint)(bVal * float(sectionHeight - 1)) + 2 * sectionHeight;
    
    float intensity = 0.5;

    if (rY < outHeight) {
        float4 current = outTexture.read(uint2(targetX, rY));
        current.r += intensity; 
        current.g += intensity * 0.1;
        current.b += intensity * 0.1;
        outTexture.write(min(current, float4(4.0)), uint2(targetX, rY));
    }
    
    if (gY < outHeight) {
         float4 current = outTexture.read(uint2(targetX, gY));
         current.g += intensity;
         current.r += intensity * 0.1;
         current.b += intensity * 0.1;
         outTexture.write(min(current, float4(4.0)), uint2(targetX, gY));
    }
    
    if (bY < outHeight) {
         float4 current = outTexture.read(uint2(targetX, bY));
         current.b += intensity;
         current.r += intensity * 0.1;
         current.g += intensity * 0.1;
         outTexture.write(min(current, float4(4.0)), uint2(targetX, bY));
    }
}
