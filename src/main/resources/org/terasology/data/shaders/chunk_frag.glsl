/*
 * Copyright 2012 Benjamin Glatzel <benjamin.glatzel@me.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

uniform sampler2D textureAtlas;
uniform sampler2D textureWaterNormal;
uniform sampler2D textureLava;
uniform sampler2D textureEffects;
uniform sampler2D textureWaterReflection;

uniform float time;
uniform float daylight = 1.0;
uniform bool swimming;
uniform bool carryingTorch;

uniform float clipHeight = 0.0;

varying vec4 vertexWorldPosRaw;
varying vec4 vertexWorldPos;
varying vec4 vertexPos;
varying vec3 eyeVec;
varying vec3 lightDir;
varying vec3 normal;

varying float flickering;
varying float flickeringAlternative;

uniform vec3 chunkOffset;
uniform vec2 waterCoordinate;
uniform vec2 lavaCoordinate;
uniform vec2 grassCoordinate;

#define DAYLIGHT_AMBIENT_COLOR 0.95, 0.92, 0.91
#define MOONLIGHT_AMBIENT_COLOR 0.8, 0.8, 1.0
#define NIGHT_BRIGHTNESS 0.05
#define WATER_COLOR 0.325, 0.419, 0.525, 0.75
#define REFLECTION_COLOR 0.95, 0.97, 1.0, 0.75

#define TORCH_WATER_SPEC 8.0
#define TORCH_WATER_DIFF 0.7
#define TORCH_BLOCK_SPEC 0.7
#define TORCH_BLOCK_DIFF 1.0
#define WATER_SPEC 2.0
#define WATER_DIFF 1.0
#define BLOCK_DIFF 0.25
#define BLOCK_AMB 1.0

#define WATER_REFRACTION 0.1

void main(){
	if (clipHeight > 0 && vertexWorldPosRaw.y < clipHeight) {
        discard;
	}

    vec4 texCoord = gl_TexCoord[0];

    vec3 normalizedVPos = -normalize(vertexWorldPos.xyz);
    vec3 normalWater;
    bool isWater = false;

    vec3 finalLightDir = lightDir;

    /* DAYLIGHT BECOMES... MOONLIGHT! */
    /* Now featuring linear interpolation to make the transition more smoothly... :-) */
    if (daylight < 0.1)
        finalLightDir = mix(finalLightDir * -1.0, finalLightDir, daylight / 0.1);

    vec4 color;

    /* APPLY WATER TEXTURE */
    if (texCoord.x >= waterCoordinate.x && texCoord.x < waterCoordinate.x + TEXTURE_OFFSET && texCoord.y >= waterCoordinate.y && texCoord.y < waterCoordinate.y + TEXTURE_OFFSET) {
        vec2 waterOffset = vec2(vertexWorldPosRaw.x + timeToTick(time, 0.1), vertexWorldPosRaw.z + timeToTick(time, 0.1)) / 8.0;
        vec2 waterOffsetLarge = vec2(vertexWorldPosRaw.x - timeToTick(time, 0.1), vertexWorldPosRaw.z + timeToTick(time, 0.1)) / 16.0;

        normalWater = (texture2D(textureWaterNormal, waterOffset) * 2.0 - 1.0).xyz;

#ifdef COMPLEX_WATER
        vec3 normalWaterLarge = (texture2D(textureWaterNormal, waterOffsetLarge) * 2.0 - 1.0).xyz;

        vec2 projectedPos = 0.5 * (vertexPos.st/vertexPos.q) + vec2(0.5);
        normalWater = mix(normalWater, normalWaterLarge, clamp(0.5 + length(projectedPos), 0.0, 1.0));

        color = texture2D(textureWaterReflection, projectedPos + normalWater.xy * WATER_REFRACTION) * vec4(REFLECTION_COLOR);

        // Fresnel
        color = mix(color, vec4(WATER_COLOR), clamp(dot(vec3(0.0, 1.0, 0.0), normalize(eyeVec)), 0.0, 1.0));
#else
        color = vec4(WATER_COLOR);
#endif

        isWater = true;
    /* APPLY LAVA TEXTURE */
    } else if (texCoord.x >= lavaCoordinate.x && texCoord.x < lavaCoordinate.x + TEXTURE_OFFSET && texCoord.y >= lavaCoordinate.y && texCoord.y < lavaCoordinate.y + TEXTURE_OFFSET) {
        texCoord.x = mod(texCoord.x, TEXTURE_OFFSET) * (1.0 / TEXTURE_OFFSET);
        texCoord.y = mod(texCoord.y, TEXTURE_OFFSET) / (128.0 / (1.0 / TEXTURE_OFFSET));
        texCoord.y += mod(timeToTick(time, 0.1), 127.0) * (1.0/128.0);

        color = texture2D(textureLava, texCoord.xy);
    /* APPLY DEFAULT TEXTURE FROM ATLAS */
    } else {
        color = texture2D(textureAtlas, texCoord.xy);
    }

    if (color.a < 0.5)
        discard;

    /* APPLY OVERALL BIOME COLOR OFFSET */
    if (!(texCoord.x >= grassCoordinate.x && texCoord.x < grassCoordinate.x + TEXTURE_OFFSET && texCoord.y >= grassCoordinate.y && texCoord.y < grassCoordinate.y + TEXTURE_OFFSET)) {
        if (gl_Color.r < 0.99 && gl_Color.g < 0.99 && gl_Color.b < 0.99) {
            if (color.g > 0.5) {
                color.rgb = vec3(color.g) * gl_Color.rgb;
            } else {
                color.rgb *= gl_Color.rgb;
            }

            color.a *= gl_Color.a;
        }
    /* MASK GRASS AND APPLY BIOME COLOR */
    } else {
        vec4 maskColor = texture2D(textureEffects, vec2(10.0 * TEXTURE_OFFSET + mod(texCoord.x,TEXTURE_OFFSET), mod(texCoord.y,TEXTURE_OFFSET)));

        // Only use one channel so the color won't be altered
        if (maskColor.a != 0.0) color.rgb = vec3(color.g) * gl_Color.rgb;
    }

    // Calculate daylight lighting value
    float daylightValue = gl_TexCoord[1].x;
    float daylightScaledValue = daylight * daylightValue;

    // Calculate blocklight lighting value
    float blocklightDayIntensity = 1.0 - daylightScaledValue;
    float blocklightValue = gl_TexCoord[1].y;

    float occlusionValue = expOccValue(gl_TexCoord[1].z);
    float diffuseLighting;

    if (isWater) {
        diffuseLighting = calcLambLight(normalWater, normalizedVPos);
    } else {
        diffuseLighting = calcLambLight(normal, finalLightDir);
    }

    float torchlight = 0.0;

    /* CALCULATE TORCHLIGHT */
    if (carryingTorch) {
        if (isWater)
            torchlight = calcTorchlight(calcLambLight(normalWater, normalizedVPos) * TORCH_WATER_DIFF
            + TORCH_WATER_SPEC * calcSpecLightWithOffset(normal, normalizedVPos, normalize(eyeVec), 64.0, normalWater), vertexWorldPos.xyz);
        else
            torchlight = calcTorchlight(calcLambLight(normal, normalizedVPos) * TORCH_BLOCK_DIFF
            + TORCH_BLOCK_SPEC * calcSpecLight(normal, normalizedVPos, normalize(eyeVec), 32.0), vertexWorldPos.xyz);
    }

    vec3 daylightColorValue;

    /* CREATE THE DAYLIGHT LIGHTING MIX */
    if (isWater) {
        /* WATER NEEDS DIFFUSE AND SPECULAR LIGHT */
        daylightColorValue = vec3(diffuseLighting) * WATER_DIFF;
        daylightColorValue += calcSpecLightWithOffset(normal, finalLightDir, normalize(eyeVec), 64.0, normalWater) * WATER_SPEC;
    } else {
        /* DEFAULT LIGHTING ONLY CONSIST OF DIFFUSE AND AMBIENT LIGHT */
        daylightColorValue = vec3(BLOCK_AMB + diffuseLighting * BLOCK_DIFF);
    }

    /* SUNLIGHT BECOMES MOONLIGHT */
    vec3 ambientTint = mix(vec3(MOONLIGHT_AMBIENT_COLOR), vec3(DAYLIGHT_AMBIENT_COLOR), daylight);
    daylightColorValue.xyz *= ambientTint;

    // Scale the lighting according to the daylight and daylight block values and add moonlight during the nights
    daylightColorValue.xyz *= daylightScaledValue + (NIGHT_BRIGHTNESS * (1.0 - daylight) * expLightValue(daylightValue));

    // Calculate the final block light brightness
    float blockBrightness = (expLightValue(blocklightValue) + diffuseLighting * blocklightValue * BLOCK_DIFF);

    torchlight -= flickeringAlternative * torchlight;

    blockBrightness += (1.0 - blockBrightness) * torchlight;
    blockBrightness -= flickering * blocklightValue;
    blockBrightness *= blocklightDayIntensity;

    // Calculate the final blocklight color value and add a slight reddish tint to it
    vec3 blocklightColorValue = vec3(blockBrightness) * vec3(1.0, 0.95, 0.94);

    // Apply the final lighting mix
    color.xyz *= (daylightColorValue + blocklightColorValue) * occlusionValue;
    gl_FragColor = color;
}
