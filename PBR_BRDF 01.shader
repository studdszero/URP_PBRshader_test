Shader "Unlit/PBR_BRDF 01"
{
    Properties
    {
    [Header(Texture)]
        _MainColorTex  ("基础颜色贴图",2D)                = "white" {}
        _NormalTex	("法线贴图", 2D)                    = "bump"  {}
		_MetallicTex    ("金属度贴图", 2d)              = "0.5" {}
        _RoughnessTex   ("粗糙度贴图",2D)               = "0.5" {}
        _EmissiveTex    ("自发光贴图", 2d)                  = "black" {}
        _OcclusionTex   ("环境遮挡图",2D)                  = "white" {}

    [Header(Diffuse)]
        _BaseColor    ("基本色",      Color)              = (1.0, 1.0, 1.0, 1.0)

    }
    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Geometry"
            "RenderType"="Opaque"
        }
     
        Pass
        {
            Tags{"LightMode"="UniversalForward"}

            HLSLPROGRAM 

            #pragma vertex vert
            #pragma fragment frag
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 3.0
            #pragma multi_compile_instancing

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT   
            //柔化阴影，得到软阴影

            // Includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderGraphFunctions.hlsl"
            #include "Packages/com.unity.shadergraph/ShaderGraphLibrary/ShaderVariablesFunctions.hlsl"
            
            //声明采样器
            TEXTURE2D(_MainColorTex);   SAMPLER(sampler_MainColorTex);
            TEXTURE2D(_NormalTex);   SAMPLER(sampler_NormalTex);
            TEXTURE2D(_MetallicTex);   SAMPLER(sampler_MetallicTex);
            TEXTURE2D(_RoughnessTex);   SAMPLER(sampler_RoughnessTex);
            TEXTURE2D(_EmissiveTex);   SAMPLER(sampler_EmissiveTex);
            TEXTURE2D(_OcclusionTex);   SAMPLER(sampler_OcclusionTex);
            //声明接口参数
            CBUFFER_START(UnityPerMaterial)
            float4 _BaseColor;

            CBUFFER_END
           
			//定义函数
			//GGX：NDF法线分布函数
			float DistributionGGX(float3 N,float3 H,float Roughness)
			{
				float a             = Roughness * Roughness;
                float a2            = a * a;
                float NdotH         = max( dot(N,H) ,0.0);
                float NdotH2        = NdotH * NdotH;
                float nominator     = a2;
                float denominator   = (NdotH2 * (a2-1.0) +1.0);
                denominator         = 3.1415926 * denominator * denominator;
                
                return   nominator/ max(denominator,0.0000001);//防止分母为0
			}

			//GeometrySchlickGGX：微表面几何遮挡函数
			float GeometrySchlickGGX(float NdotV,float Roughness)
			{
                float r = Roughness +1.0;
                float k = r * r / 8.0;
                float nominator = NdotV;
                float denominator = k + (1.0-k) * NdotV;
        
                return   nominator/ max(denominator,0.0000001);//防止分母为0
			}
            float GeometrySmith(float3 N,float3 V,float3 L,float Roughness)
            {
                float NdotV = max(dot(N,V),0.0);
                float NdotL = max(dot(N,L),0.0);

                float GGX1 = GeometrySchlickGGX(NdotV,Roughness);
                float GGX2 = GeometrySchlickGGX(NdotL,Roughness);

                return GGX1 * GGX2;
            }

            //Fresnel-Schlick：菲涅尔函数
			float3 FresnelSchlick(float HdotV, float3 F0)
			{
				return F0 + (1.0 - F0) * pow(1.0 - HdotV, 5);
			}

            float3 FresnelSchlickRoughness(float NdotV,float3 F0,float Roughness)
            {
                return F0+(max(float3(1.0-Roughness,1.0-Roughness,1.0-Roughness),F0)-F0)*pow(1.0-NdotV,5.0);
            }

            //球谐基函数
            float3 SH_indirectDiffuse(float3 N)
            {
                float4 SHCoefficients[7];
                SHCoefficients[0] = unity_SHAr;
                SHCoefficients[1] = unity_SHAg;
                SHCoefficients[2] = unity_SHAb;
                SHCoefficients[3] = unity_SHBr;
                SHCoefficients[4] = unity_SHBg;
                SHCoefficients[5] = unity_SHBb;
                SHCoefficients[6] = unity_SHC;
                float3 Color = SampleSH9(SHCoefficients,N);
                return max(0,Color);
            }
            
            //间接高光 调用反射探针
            float3 IndirSpeCube(float3 V,float3 N,float Roughness,float AO)
            {
                float3 VdotN=reflect(-V,N);
                Roughness = Roughness*(1.7-0.7*Roughness);  //Unity内部不是线性 调整下拟合曲线求近似
                float MidLevel = Roughness*6;  //转换MIP为线性等级，换算MIP层级为6,把粗糙度remap到0-6 7个阶级 然后进行lod采样
                float4 EnvSpecularColor = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0,VdotN,MidLevel); //根据不同的等级进行采样
                #if !defined(UNITY_USE_NATIVE_HDR)
                return DecodeHDREnvironment(EnvSpecularColor,unity_SpecCube0_HDR).rgb*AO;  //用DecodeHDREnvironment将颜色从HDR编码下解码
                #else
                return EnvSpecularColor.rgb*AO;
                #endif
            }

            // LUT拟合函数 输入粗糙度次方，BRDF高光项
            float3 IndirSpeFactor(float roughness,float smoothness,float3 BRDFspe,float3 F0,float NdotV)
            {
                #ifdef UNITY_COLORSPACE_GAMMA
                float SurReduction=1-0.28*roughness,roughness;
                #else
                float SurReduction=1/(roughness*roughness+1);
                #endif
                #if defined(SHADER_API_GLES)  //Lighting.hlsl 261行，拟合LUT
                float Reflectivity=BRDFspe.x;   
                #else
                float Reflectivity=max(max(BRDFspe.x,BRDFspe.y),BRDFspe.z);
                #endif
                half GrazingTSection=saturate(Reflectivity + smoothness);
                float Fre=Pow4(1-NdotV);  //lighting.hlsl第501行 
                //float Fre=exp2((-5.55473*NdotV-6.98316)*NdotV);//lighting.hlsl第501行 它是4次方 我是5次方 
                return lerp(F0,GrazingTSection,Fre)*SurReduction;
            }
         
            //ToneMapping：色调映射
            float3 ACESToneMapping(float3 x)
            {
                float a = 2.51f;
                float b = 0.03f;
                float c = 2.43f;
                float d = 0.59f;
                float e = 0.14f;
                return saturate((x*(a*x+b))/(x*(c*x+d)+e));
            }
            float4 ACESToneMapping(float4 x)
            {
                float a = 2.51f;
                float b = 0.03f;
                float c = 2.43f;
                float d = 0.59f;
                float e = 0.14f;
                return saturate((x*(a*x+b))/(x*(c*x+d)+e));
            }
         
            //输入结构  
            struct VertexInput
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv0 : TEXCOORD0;
                float4 tangent : TANGENT; 
            };
            //输出结构
            struct VertexOutput
            {
                float4 pos : SV_POSITION;
                float3 posWS :TEXCOORD0;
                float3 nDirWS : TEXCOORD1;  // 世界空间法线信息
                float3 tDirWS : TEXCOORD2;  // 世界空间切线信息
                float3 bDirWS : TEXCOORD3;  // 世界空间切线信息  
                float2 uv0 : TEXCOORD4;
            };

            VertexOutput vert(VertexInput v) {
                VertexOutput o = (VertexOutput)0;
                o.pos = TransformObjectToHClip( v.vertex.xyz );
                o.posWS = TransformObjectToWorld(v.vertex.xyz);
                o.nDirWS = TransformObjectToWorldNormal(v.normal);                                  // 世界空间法线信息
                o.tDirWS = normalize(TransformObjectToWorldDir(v.tangent.xyz));                             // 世界空间切线信息
                o.bDirWS = normalize(cross(o.nDirWS, o.tDirWS) * v.tangent.w);                      // 世界空间切线信息
                o.uv0 = v.uv0;
                return o;
            }

            float4 frag(VertexOutput i):SV_Target {

                //准备光照参数
                float4 SHADOW_COORDS = TransformWorldToShadowCoord(i.posWS);              
                Light mainlight = GetMainLight(SHADOW_COORDS);
                float shadow = mainlight.shadowAttenuation;
                //准备向量
                float3 nDirTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalTex,sampler_NormalTex,i.uv0));         // 采样法线纹理并解码 切线空间nDir
                float3x3 TBN = float3x3(i.tDirWS,i.bDirWS,i.nDirWS);                                        // 构建TBN矩阵
                float3 nDirWS = normalize(mul(nDirTS, TBN));                                                // 世界空间nDir

                float3 lDirWS = normalize(mainlight.direction) ;
                float3 vDirWS = normalize(_WorldSpaceCameraPos.xyz - i.posWS.xyz) ;
                float3 hDirWS = normalize(vDirWS + lDirWS);
                float3 vrDirWS = reflect(-vDirWS,nDirWS);

                //准备中间量
                float ndotl = max(dot(nDirWS,lDirWS),0.0);          
                float ndotv = max(dot(nDirWS, vDirWS),0.0);  
                float hdotv = max(dot(hDirWS, vDirWS),0.0);

                //采样纹理
                float4 var_MainColorTex = SAMPLE_TEXTURE2D(_MainColorTex, sampler_MainColorTex, i.uv0); 
                float4 var_MetallicTex = SAMPLE_TEXTURE2D(_MetallicTex, sampler_MetallicTex, i.uv0);   
                float4 var_RoughnessTex = SAMPLE_TEXTURE2D(_RoughnessTex, sampler_RoughnessTex, i.uv0);   
                float4 var_EmissiveTex = SAMPLE_TEXTURE2D(_EmissiveTex, sampler_EmissiveTex, i.uv0);   
                float4 var_OcclusionTex = SAMPLE_TEXTURE2D(_OcclusionTex, sampler_OcclusionTex, i.uv0);    
                

                float3 F0 = lerp(0.04,var_MainColorTex.rgb,var_MetallicTex.r);
                float3 Radiance = mainlight.color;

            ///////////////////////////////直接光照///////////////////////////////
                
                //高光部分
                float D = DistributionGGX(nDirWS,hDirWS,var_RoughnessTex.r);
                float G = GeometrySmith(nDirWS,vDirWS,lDirWS,var_RoughnessTex.r);
                float3 F = FresnelSchlick(hdotv,F0);

                float3 nominator  = D * F * G;
                float denominator =  max(4 * ndotv * ndotl, 0.001);
                float3 Specular = nominator/denominator;

                //漫反射部分
				float3 KS = F;
				float3 KD = 1-KS;
				KD*=1-var_MetallicTex.r;
				float3 Diffuse = KD * var_MainColorTex.rgb ; //没有除以 UNITY_PI

                //高光+漫反射 
				float3 DirectLight = (Diffuse + Specular) * ndotl  * Radiance *  _BaseColor.rgb ;

            ////////////////////////////////间接光照////////////////////////////////
            
                //漫反射部分        调用球谐基函数
                float3 irradianceSH9 = SH_indirectDiffuse(nDirWS) * var_OcclusionTex.r ;
                //计算间接光的菲涅尔系数和kd
                float3 F_IndirectLight = FresnelSchlickRoughness(ndotv,F0,var_RoughnessTex.r);
                float3 KD_IndirectLight = (1 - F_IndirectLight) * (1 - var_MetallicTex.r);

                float3 Diffuse_Indirect = irradianceSH9 * var_MainColorTex.rgb * KD_IndirectLight; //没有除以 UNITY_PI
                      
                //高光部分      反射探针
                //转换MIP为线性等级，换算MIP层级为6，采样 cubemap
                float3 IndirSpeCubeColor=IndirSpeCube(vDirWS,nDirWS,var_RoughnessTex.r,var_OcclusionTex.r);
                //函数拟合LUT
                float roughness02 = (1-var_RoughnessTex.r)* (1-var_RoughnessTex.r);
                float3 IndirSpeCubeFactor=IndirSpeFactor(roughness02,var_RoughnessTex.r,Specular,F0,ndotv);         //粗糙度二次方
                // float3 IndirSpeCubeFactor=IndirSpeFactor(var_RoughnessTex.r,var_RoughnessTex.r,Specular,F0,ndotv);
           
                //间接高光 * 拟合高光因子
                float3 Specular_Indirect = IndirSpeCubeColor * IndirSpeCubeFactor;

                //间接高光 + 间接漫反射
                float3 IndirectLight = Diffuse_Indirect + Specular_Indirect  ;


                //最终颜色输出
                float4 FinalColor = 0 ;

                FinalColor.rgb = (DirectLight + IndirectLight) * shadow ;

                FinalColor.rgb += var_EmissiveTex.rgb ;

                //HDR>>>LDR
                FinalColor.rgb = ACESToneMapping(FinalColor.rgb);
              

                return  FinalColor ;
            }
            ENDHLSL  
 
        }

       
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        // unity自带投影

    }
    FallBack "Hidden/Shader Graph/FallbackError"
}