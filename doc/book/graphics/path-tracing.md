# Path Tracing Theory Primer

This primer gives a high-level overview of the physical and mathematical principles behind path tracing, derived from the Rendering Equation. It was written for the compute-shader path tracer of [resin](https://github.com/tsnl/resin/tree/archive/main-v3/src/resin), and describes the lighting the [graphics plan](plan.md) leaves for after rasterization.

## 1. The Rendering Equation

At its core, physically based rendering solves Kajiya's Rendering Equation. For a point $p$ on a surface, the outgoing radiance $L_o$ in a direction $\omega_o$ is the sum of emitted light and reflected light:

$$ L_o(p, \omega_o) = L_e(p, \omega_o) + \int_{\Omega} f_r(p, \omega_i, \omega_o) L_i(p, \omega_i) (\omega_i \cdot n) d\omega_i $$

Where:
*   $L_e$: Emitted light (if the object glows).
*   $\int_{\Omega}$: Integral over the hemisphere of all incoming light directions.
*   $f_r$: The **BRDF** (Bidirectional Reflectance Distribution Function).
*   $L_i$: Incoming radiance from direction $\omega_i$.
*   $(\omega_i \cdot n)$: The cosine law (Lambert's law), attenuating light based on the angle of incidence.

## 2. The BRDF ($f_r$)

The BRDF defines how a material reflects light. In modern PBR (Physically Based Rendering), the Cook-Torrance microfacet model is the standard. It splits into diffuse and specular terms:

$$ f_r = k_d f_{lambert} + k_s f_{microfacet} $$

### Diffuse Term ($f_{lambert}$)
Models light that enters the surface, scatters internally, and exits in a random direction.
$$ f_{lambert} = \frac{c}{\pi} $$
Where $c$ is the albedo color. The $\frac{1}{\pi}$ ensures energy conservation when integrating over the hemisphere.

### Specular Term ($f_{microfacet}$)
Models the surface as millions of microscopic mirrors.
$$ f_{specular} = \frac{D(h) F(v, h) G(l, v, h)}{4 (\omega_i \cdot n) (\omega_o \cdot n)} $$

This is composed of three statistical functions:
1.  **D (Normal Distribution Function):** Fraction of microfacets aligned to reflect light from $\omega_i$ to $\omega_o$. (e.g., GGX/Trowbridge-Reitz).
2.  **F (Fresnel Equation):** Fraction of light that reflects vs. refracts/absorbs based on view angle. (e.g., Schlick's Approximation).
3.  **G (Geometry Function):** Fraction of microfacets not blocked (shadowed/masked) by others. (e.g., Smith-GGX).

## 3. The Monte Carlo Estimator

The integration $\int_{\Omega}$ is impossible to solve analytically for complex scenes. Path tracing approximates it using Monte Carlo integration:

$$ L_o \approx \frac{1}{N} \sum_{k=1}^{N} \frac{f_r(\omega_i, \omega_o) L_i(\omega_i) (\omega_i \cdot n)}{p(\omega_i)} $$

*   $N$: Number of samples (rays).
*   $p(\omega_i)$: The **Probability Density Function (PDF)**—the likelihood of choosing a specific random direction.

To reduce variance (noise), we use **Importance Sampling**, choosing directions where light is likely to come from (e.g., towards the sun) or where the BRDF is strong (e.g., the specular reflection angle).

The term commonly tracked in a path tracer's "throughput" is the weight:
$$ \text{Throughput} = \frac{f_r(\omega_i, \omega_o) (\omega_i \cdot n)}{p(\omega_i)} $$

When the PDF $p(\omega_i)$ is perfectly matched to the BRDF geometry (e.g., Cosine-weighted sampling for diffuse), terms cancel out effectively:
$$ \text{Diffuse Weight} = \frac{(\frac{c}{\pi}) (\omega_i \cdot n)}{\frac{\omega_i \cdot n}{\pi}} = c $$

---

## 4. Q&A: From First Principles

### Q: Why is the integral a simple multiplication? Why not a more complex function?
The integral form $\int f_r \cdot L_i \cdot (n \cdot \omega_i)$ relies on two key physical assumptions:
1.  **Linearity (Superposition):** Light does not interact with other light. The result of two light sources is simply the sum of them individually. This allows us to use an integral (a continuous sum).
2.  **Locality:** The strict definition of a BRDF assumes light enters and exits at the exact same point ($x_i = x_o$).
    *   For metals, this is true (reflection is immediate).
    *   For dielectrics (plastic/paint), light penetrates but exits so close to the entry point that it appears local.
    *   *Note:* Materials where this fails (skin, wax) require a BSSRDF (Subsurface Scattering), which integrates over an area, not just a hemisphere.

### Q: Why split materials into Lambertian + Specular?
This split models the two distinct paths a photon takes when hitting a dielectric interface:
1.  **Path A (Specular):** The photon hits the surface boundary and reflects immediately due to Fresnel forces. It interacts only with the surface, not the pigments inside.
2.  **Path B (Diffuse):** The photon enters the material (refracts), hits pigment particles, scatters chaotically, and exits in a random direction.
The "Russian Roulette" logic in path tracing (choosing to bounce diffusely OR specularly) explicitly models this bifurcation.

### Q: Why do we multiply by $(\omega_i \cdot n)$ but then divide by it in the Specular BRDF?
1.  **The Multiplier $(\omega_i \cdot n)$:** This is the **Cosine Law**. It effectively spreads the light energy over a larger area when hitting a surface at a glancing angle. A tilted surface physically intercepts fewer photons.
2.  **The Denominator:** The Microfacet BRDF contains a division by $4 (\omega_i \cdot n) (\omega_o \cdot n)$. This is a Jacobian correction factor. It converts the distribution of *microfacets* (which don't care about the macro-surface normal) into the macroscopic reflection ratio.
3.  **The Result:** For specular reflections, the two terms cancel out. This physically means a mirror doesn't get darker at grazing angles; it simply reflects a larger slice of the environment. For diffuse surfaces, the denominator doesn't exist, so the cosine law applies, and the surface darkens as it turns away from the light.

### Q: Is the Geometry (G) term actually important?
Yes, it is critical for energy conservation. Without $G$, the specular term would divide by zero near grazing angles ($(\omega_i \cdot n) \approx 0$), causing edges to glow infinitely bright. $G$ represents **micro-shadowing** and **masking**—at grazing angles, surface bumps block most light, mathematically cancelling the singularity and keeping the result finite.

### Q: Why does Fresnel's Equation make sense physically?
Why do surfaces become mirrors at grazing angles?
*   **Physics:** When a light wave hits a surface head-on, it "sees" the empty space between atoms and enters (refracts).
*   **Grazing Angle:** The surface appears compressed to the incoming wave. Atoms appear stacked impenetrably tight, presenting a "wall" of electrons. The wave cannot penetrate and is forced to bounce off (reflect).
This is why even matte objects (asphalt, Toast) exhibit specular reflections at extreme grazing angles.
