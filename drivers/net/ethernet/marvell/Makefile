# SPDX-License-Identifier: GPL-2.0
#
# Makefile for the Marvell device drivers.
#

obj-$(CONFIG_MVMDIO) += mvmdio.o
obj-$(CONFIG_MV643XX_ETH) += mv643xx_eth.o
obj-$(CONFIG_MVNETA_BM) += mvneta_bm.o
obj-$(CONFIG_MVNETA) += mvneta.o
obj-$(CONFIG_MVPP2) += mvpp2/
obj-$(CONFIG_PXA168_ETH) += pxa168_eth.o
obj-$(CONFIG_SKGE) += skge.o
obj-$(CONFIG_SKY2) += sky2.o
obj-y		+= octeon_ep/
obj-y		+= octeon_ep_vf/
obj-y		+= octeontx2/
obj-y		+= prestera/

# Bonnell: sky2 is on the Rx/Tx hot path, build it with -O3
ifdef CONFIG_X86_BONNELL_HOT_O3
CFLAGS_sky2.o += -O3
endif
