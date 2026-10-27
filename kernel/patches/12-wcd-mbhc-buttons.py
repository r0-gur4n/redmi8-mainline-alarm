#!/usr/bin/env python3
"""Step 12: stop the MBHC from leaving a headset button stuck on removal.

The PM8953 MBHC can decode a headphone-removal transient as BTN3, which the
qcom machine driver maps to KEY_VOLUMEDOWN.  The mainline removal path only
reports the headphone/headset bits, never releases the button bits, so the key
stays logically pressed and the volume falls continuously.

Only BTN0 is meaningful while detect_accessory_type is set (it distinguishes a
3-pole headphone from a headset), so ignore the other buttons in that window
and release all button bits on removal.

    python3 12-wcd-mbhc-buttons.py <kernel-tree>
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
    """\tbtn_result = snd_soc_component_read(component, CDC_A_MBHC_RESULT_1) &
\t\t\t\t  CDC_A_MBHC_RESULT_1_BTN_RESULT_MASK;

\tswitch (btn_result) {""",
    """\tbtn_result = snd_soc_component_read(component, CDC_A_MBHC_RESULT_1) &
\t\t\t\t  CDC_A_MBHC_RESULT_1_BTN_RESULT_MASK;

\t/*
\t * While detect_accessory_type is set (before insertion and after
\t * removal) only BTN0 is meaningful: it is used to tell a 3-pole
\t * headphone from a headset.  A removal transient can otherwise be
\t * decoded as BTN3 and leave KEY_VOLUMEDOWN stuck.
\t */
\tif (priv->detect_accessory_type && btn_result != 0x0)
\t\treturn IRQ_HANDLED;

\tswitch (btn_result) {""")

replace_once(
    """\t} else { /* removal */
\t\treport = 0;
\t\tpriv->detect_accessory_type = true;
\t\tpriv->mbhc_btn0_released = false;
\t}""",
    """\t} else { /* removal */
\t\treport = 0;
\t\tpriv->detect_accessory_type = true;
\t\tpriv->mbhc_btn0_released = false;
\t\t/* Release any button that was reported before the removal. */
\t\tsnd_soc_jack_report(priv->jack, 0, btn_mask);
\t}""")

p.write_text(s)
print('patched:', p)
