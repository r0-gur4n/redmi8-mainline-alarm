#!/usr/bin/env python3
"""Step 13: enable the PM8953/WCD audio path and the AW87519 speaker amp.

The Redmi 8 has a PM8953 USID1 analog codec (no mainline MFD match for the
USID1 revision block, so the DTS overrides the compatible with the two-USID
PM8937 entry), a QDSP6 sound card, and an AW87519 I2C speaker PA with its
RESETB line on TLMM GPIO 125.

This step adds:

  * the PM8953 analog codec node (disabled; the board DTS enables it),
  * the QDSP6 sound card, DAI links and CDC PDM pinctrl,
  * the board sound/codec routing, PMIC compatible override, AW87519 reset
    hog and amplifier node.

The codec driver changes are steps 11 and 12; the board DTB is then passed
through the kernel/devicetree 1/2/3 scripts.

    python3 13-dts-audio.py <kernel-tree>
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    sys.exit(__doc__)
tree = Path(sys.argv[1])


def replace_once(path, old, new):
    s = path.read_text()
    assert s.count(old) == 1, (path, s.count(old))
    path.write_text(s.replace(old, new, 1))


DTS = tree / "arch/arm64/boot/dts/qcom/sdm439-xiaomi-olive.dts"
PMIC = tree / "arch/arm64/boot/dts/qcom/pm8953.dtsi"
QDSP6 = tree / "arch/arm64/boot/dts/qcom/msm8937-qdsp6.dtsi"

replace_once(DTS, """&adsp_mem {
	size = <0x0 0x1800000>;
	status = "okay";
};

&blsp1_uart2 {""", """&adsp_mem {
	size = <0x0 0x1800000>;
	status = "okay";
};

&apr {
	status = "okay";
};

&lpass_codec {
	status = "okay";
};

&sound {
	model = "xiaomi-olive";

	audio-routing =
		"AMIC1", "MIC BIAS External1",
		"AMIC2", "MIC BIAS Internal2",
		"AMIC3", "MIC BIAS External1",
		"MM_DL1", "MultiMedia1 Playback",
		"MM_DL3", "MultiMedia3 Playback",
		"MM_DL4", "MultiMedia4 Playback",
		"MultiMedia2 Capture", "MM_UL2";

	status = "okay";
};

&wcd_codec {
	qcom,hphl-jack-type-normally-open;
	qcom,mbhc-vthreshold-high = <75 150 225 450 500>;
	qcom,mbhc-vthreshold-low = <75 150 225 450 500>;
	qcom,micbias1-ext-cap;

	vdd-cdc-io-supply = <&pm8953_l5>;
	vdd-cdc-tx-rx-cx-supply = <&pm8953_s4>;
	vdd-micbias-supply = <&pm8953_l13>;
	status = "okay";
};

/*
 * PM8953 USID1 hosts the WCD analog codec but does not expose the PMIC
 * revision block that pmic-spmi reads during probe.  With the default
 * "qcom,spmi-pmic" fallback (one USID) the read fails and the driver is
 * rejected, so codec@f000 never gets instantiated.  Match a two-USID
 * compatible instead, which makes pmic-spmi inherit the revision info
 * from the base USID (pmic@0) and then populate this node's children.
 */
&spmi_bus {
	pmic@1 {
		compatible = "qcom,pm8937", "qcom,spmi-pmic";
	};
};

/*
 * AW87519 speaker smart PA reset (RESETB, active low), on TLMM GPIO 125.
 * There is no mainline driver for it yet, so hold the line released from
 * boot to keep the amplifier in its default pass-through mode.
 */
&tlmm {
	aw87519_reset: aw87519-reset {
		gpio-hog;
		gpios = <125 GPIO_ACTIVE_HIGH>;
		output-high;
		line-name = "aw87519-reset";
	};
};

&blsp1_i2c2 {
	status = "okay";

	speaker_amp: amplifier@58 {
		compatible = "awinic,aw87519";
		reg = <0x58>;
	};
};

&blsp1_uart2 {""")
replace_once(PMIC, """	pmic@1 {
		compatible = "qcom,pm8953", "qcom,spmi-pmic";
		reg = <1 SPMI_USID>;
		#address-cells = <1>;
		#size-cells = <0>;
	};""", """	pmic@1 {
		compatible = "qcom,pm8953", "qcom,spmi-pmic";
		reg = <1 SPMI_USID>;
		#address-cells = <1>;
		#size-cells = <0>;

		wcd_codec: codec@f000 {
			compatible = "qcom,pm8916-wcd-analog-codec";
			reg = <0xf000 0x200>;
			reg-names = "pmic-codec-core";
			clocks = <&q6afecc LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE
					   LPASS_CLK_ATTRIBUTE_COUPLE_NO>;
			clock-names = "mclk";
			interrupt-parent = <&spmi_bus>;
			interrupts = <0x1 0xf0 0x0 IRQ_TYPE_NONE>,
				     <0x1 0xf0 0x1 IRQ_TYPE_NONE>,
				     <0x1 0xf0 0x2 IRQ_TYPE_NONE>,
				     <0x1 0xf0 0x3 IRQ_TYPE_NONE>,
				     <0x1 0xf0 0x4 IRQ_TYPE_NONE>,
				     <0x1 0xf0 0x5 IRQ_TYPE_NONE>,
				     <0x1 0xf0 0x6 IRQ_TYPE_NONE>,
				     <0x1 0xf0 0x7 IRQ_TYPE_NONE>,
				     <0x1 0xf1 0x0 IRQ_TYPE_NONE>,
				     <0x1 0xf1 0x1 IRQ_TYPE_NONE>,
				     <0x1 0xf1 0x2 IRQ_TYPE_NONE>,
				     <0x1 0xf1 0x3 IRQ_TYPE_NONE>,
				     <0x1 0xf1 0x4 IRQ_TYPE_NONE>,
				     <0x1 0xf1 0x5 IRQ_TYPE_NONE>;
			interrupt-names = "cdc_spk_cnp_int",
					  "cdc_spk_clip_int",
					  "cdc_spk_ocp_int",
					  "mbhc_ins_rem_det1",
					  "mbhc_but_rel_det",
					  "mbhc_but_press_det",
					  "mbhc_ins_rem_det",
					  "mbhc_switch_int",
					  "cdc_ear_ocp_int",
					  "cdc_hphr_ocp_int",
					  "cdc_hphl_ocp_det",
					  "cdc_ear_cnp_int",
					  "cdc_hphr_cnp_int",
					  "cdc_hphl_cnp_int";

			#sound-dai-cells = <1>;

			status = "disabled";
		};
	};""")
QDSP6.write_text("""// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (c) 2025, Vasiliy Doylov (NekoCWD) <nekodevelopper@gmail.com>
 */
#include <dt-bindings/sound/qcom,q6voice.h>
#include <dt-bindings/sound/qcom,q6afe.h>
#include <dt-bindings/sound/qcom,q6asm.h>

&sound {
	pinctrl-0 = <&cdc_pdm_lines_default>;
	pinctrl-1 = <&cdc_pdm_lines_sleep>;
	pinctrl-names = "default", "sleep";

	mm1-dai-link {
		link-name = "MultiMedia1";
		cpu {
			sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA1>;
		};
	};

	mm2-dai-link {
		link-name = "MultiMedia2";
		cpu {
			sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA2>;
		};
	};

	mm3-dai-link {
		link-name = "MultiMedia3";
		cpu {
			sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA3>;
		};
	};

	mm4-dai-link {
		link-name = "MultiMedia4";
		cpu {
			sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA4>;
		};
	};

	primary-mi2s-dai-link {
		link-name = "Primary MI2S";
		cpu {
			sound-dai = <&q6afedai PRIMARY_MI2S_RX>;
		};

		platform {
			sound-dai = <&q6routing>;
		};

		codec {
			sound-dai = <&lpass_codec 0>, <&wcd_codec 0>;
		};
	};

	tertiary-mi2s-dai-link {
		link-name = "Tertiary MI2S";
		cpu {
			sound-dai = <&q6afedai TERTIARY_MI2S_TX>;
		};

		platform {
			sound-dai = <&q6routing>;
		};

		codec {
			sound-dai = <&lpass_codec 1>, <&wcd_codec 1>;
		};
	};

	voicemmode1-dai-link {
		link-name = "VoiceMMode1";
		cpu {
			sound-dai = <&q6voicedai VOICEMMODE1>;
		};
	};
};

&tlmm {
	cdc_pdm_lines_default: cdc-pdm-lines-default-state {
		cdc-pdm-line1-pins {
			pins = "gpio69", "gpio73", "gpio74";
			function = "cdc_pdm0";
			drive-strength = <8>;
		};

		cdc-pdm-line2-pins {
			pins = "gpio70", "gpio71", "gpio72";
			function = "cdc_pdm0";
			drive-strength = <8>;
		};
	};

	cdc_pdm_lines_sleep: cdc-pdm-lines-sleep-state {
		cdc-pdm-line1-pins {
			pins = "gpio69", "gpio73", "gpio74";
			function = "cdc_pdm0";
			drive-strength = <2>;
			bias-disable;
		};

		cdc-pdm-line2-pins {
			pins = "gpio70", "gpio71", "gpio72";
			function = "cdc_pdm0";
			drive-strength = <2>;
			bias-disable;
		};
	};
};
""")
print("audio DTS ok")
