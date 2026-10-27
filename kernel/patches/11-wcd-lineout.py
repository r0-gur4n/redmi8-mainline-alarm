#!/usr/bin/env python3
"""Step 11: add the PM8953 LINEOUT path used by the AW87519 speaker PA.

The stock olive mixer routes speaker playback through

    RX1 -> RX3 -> LINEOUT DAC -> LINE_OUT -> LINEOUT PA -> LINEOUT pin

into the AW87519. Mainline's msm8916-wcd-analog driver only implements the
class-D SPK path, so the external amplifier never receives a signal.

    python3 11-wcd-lineout.py <kernel-tree>
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    sys.exit(__doc__)
tree = Path(sys.argv[1])
p = tree / 'sound/soc/codecs/msm8916-wcd-analog.c'
s = p.read_text()


def replace_once(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old.splitlines()[0])
    s = s.replace(old, new, 1)


replace_once(
    """#define CDC_A_SPKR_DRV_DBG\t\t(0xf1B7)
#define CDC_A_CURRENT_LIMIT\t\t(0xf1C0)""",
    """#define CDC_A_SPKR_DRV_DBG\t\t(0xf1B7)

/* Lineout (used by external speaker PA on some boards, e.g. AW87519) */
#define CDC_A_RX_LO_DAC_CTL\t\t(0xf1AC)
#define RX_LO_DAC_CTL_LO_DAC_RESET_MASK\tBIT(3)
#define RX_LO_DAC_CTL_LO_DAC_RESET\tBIT(3)
#define RX_LO_DAC_CTL_LO_DAC_EN_MASK\tBIT(6)
#define RX_LO_DAC_CTL_LO_DAC_EN\t\tBIT(6)
#define RX_LO_DAC_CTL_LO_DAC_MUTE_MASK\tBIT(7)
#define RX_LO_DAC_CTL_LO_DAC_MUTE\tBIT(7)
#define CDC_A_RX_LO_EN_CTL\t\t(0xf1AD)
#define RX_LO_EN_CTL_LO_EN_MASK\t\tBIT(5)
#define RX_LO_EN_CTL_LO_EN\t\tBIT(5)
#define RX_LO_EN_CTL_LO_PA_EN_MASK\tBIT(6)
#define RX_LO_EN_CTL_LO_PA_EN\t\tBIT(6)
#define RX_LO_EN_CTL_LO_DAC_EN_MASK\tBIT(7)
#define RX_LO_EN_CTL_LO_DAC_EN\t\tBIT(7)

#define CDC_A_CURRENT_LIMIT\t\t(0xf1C0)""")

replace_once(
    """static const struct snd_kcontrol_new hphr_mux = SOC_DAPM_ENUM("HPHR", hph_enum);
""",
    """static const struct snd_kcontrol_new hphr_mux = SOC_DAPM_ENUM("HPHR", hph_enum);
static const struct snd_kcontrol_new lineout_mux = SOC_DAPM_ENUM("LINE_OUT",
\t\t\t\t\t\t\t\t  hph_enum);
""")

replace_once(
    """static int pm8916_wcd_analog_enable_hph_pa(struct snd_soc_dapm_widget *w,""",
    """static int pm8916_wcd_analog_enable_lineout_dac(struct snd_soc_dapm_widget *w,
\t\t\t\t\t\tstruct snd_kcontrol *kcontrol,
\t\t\t\t\t\tint event)
{
\tstruct snd_soc_component *component = snd_soc_dapm_to_component(w->dapm);

\tswitch (event) {
\tcase SND_SOC_DAPM_PRE_PMU:
\t\tsnd_soc_component_update_bits(component, CDC_D_CDC_ANA_CLK_CTL,
\t\t\t\t\t      BIT(4), BIT(4));
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_EN_CTL,
\t\t\t\t\t      RX_LO_EN_CTL_LO_EN_MASK |
\t\t\t\t\t      RX_LO_EN_CTL_LO_DAC_EN_MASK,
\t\t\t\t\t      RX_LO_EN_CTL_LO_EN |
\t\t\t\t\t      RX_LO_EN_CTL_LO_DAC_EN);
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_DAC_CTL,
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_RESET_MASK |
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_EN_MASK,
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_RESET |
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_EN);
\t\tbreak;
\tcase SND_SOC_DAPM_POST_PMU:
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_DAC_CTL,
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_MUTE_MASK,
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_MUTE);
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_DAC_CTL,
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_RESET_MASK, 0);
\t\tbreak;
\tcase SND_SOC_DAPM_POST_PMD:
\t\t/* Wait for 20ms before powerdown of lineout DAC */
\t\tmsleep(20);
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_DAC_CTL,
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_MUTE_MASK, 0);
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_DAC_CTL,
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_EN_MASK, 0);
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_DAC_CTL,
\t\t\t\t\t      RX_LO_DAC_CTL_LO_DAC_RESET_MASK, 0);
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_EN_CTL,
\t\t\t\t\t      RX_LO_EN_CTL_LO_DAC_EN_MASK, 0);
\t\tsnd_soc_component_update_bits(component, CDC_A_RX_LO_EN_CTL,
\t\t\t\t\t      RX_LO_EN_CTL_LO_EN_MASK, 0);
\t\tsnd_soc_component_update_bits(component, CDC_D_CDC_ANA_CLK_CTL,
\t\t\t\t\t      BIT(4), 0);
\t\tbreak;
\t}
\treturn 0;
}

static int pm8916_wcd_analog_enable_hph_pa(struct snd_soc_dapm_widget *w,""")

replace_once(
    """\t{"SPK DAC", "Switch", "PDM_RX3"},
""",
    """\t{"SPK DAC", "Switch", "PDM_RX3"},

\t/* Lineout (external speaker PA, e.g. AW87519) */
\t{"LINEOUT", NULL, "LINEOUT PA"},
\t{"LINEOUT PA", NULL, "RX_BIAS"},
\t{"LINEOUT PA", NULL, "LINE_OUT"},
\t{"LINE_OUT", "Switch", "LINEOUT DAC"},
\t{"LINEOUT DAC", NULL, "PDM_RX3"},
""")

replace_once(
    """\t\t\t   SND_SOC_DAPM_PRE_PMD | SND_SOC_DAPM_POST_PMD),
\tSND_SOC_DAPM_REGULATOR_SUPPLY("vdd-micbias", 0, 0),""",
    """\t\t\t   SND_SOC_DAPM_PRE_PMD | SND_SOC_DAPM_POST_PMD),

\t/* Lineout (external speaker PA, e.g. AW87519) */
\tSND_SOC_DAPM_OUTPUT("LINEOUT"),
\tSND_SOC_DAPM_PGA("LINEOUT PA", CDC_A_RX_LO_EN_CTL,
\t\t\t 6, 0, NULL, 0),
\tSND_SOC_DAPM_MUX("LINE_OUT", SND_SOC_NOPM, 0, 0, &lineout_mux),
\tSND_SOC_DAPM_DAC_E("LINEOUT DAC", NULL, SND_SOC_NOPM, 0, 0,
\t\t\t   pm8916_wcd_analog_enable_lineout_dac,
\t\t\t   SND_SOC_DAPM_PRE_PMU | SND_SOC_DAPM_POST_PMU |
\t\t\t   SND_SOC_DAPM_POST_PMD),
\tSND_SOC_DAPM_REGULATOR_SUPPLY("vdd-micbias", 0, 0),""")

p.write_text(s)
print('patched:', p)
