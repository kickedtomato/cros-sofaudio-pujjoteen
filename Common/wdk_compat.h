/*
 * wdk_compat.h - forced include for SklHdaudBus on WDK 10.0.28000.
 *
 * WDK 10.0.28000's shared/d3dkmddi.h declares DXGKARG_NOTIFY_CONTEXT_QOS_CHANGE
 * with a D3DDDI_QOS member, but no header in that kit defines D3DDDI_QOS.
 * SklHdaudBus includes d3dkmddi.h only for the SGPC graphics-power callbacks
 * and never touches that struct, so a placeholder type is enough to compile.
 * SklHdaudBus.vcxproj force-includes this file only for that WDK version.
 */
#pragma once
typedef struct _D3DDDI_QOS_PLACEHOLDER { unsigned int Reserved; } D3DDDI_QOS;
