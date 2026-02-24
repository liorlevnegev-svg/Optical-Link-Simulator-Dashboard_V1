# Optical Link Simulator Dashboard

![LEVTRONICS Logo](LevTronics Logo V2.jpeg)

A comprehensive MATLAB-based simulation dashboard for analyzing and calculating performance parameters of optical links across satellite data relay constellations. 

## Overview
This tool allows engineers and researchers to simulate optical communication routing, evaluating both Direct-to-Earth (DTE) and Inter-Satellite Links (ISL). It calculates complex link budgets, including Free-Space Path Loss (FSPL), geometric coupling, pointing loss, atmospheric attenuation, and total hop latency.

## Features
* **Interactive Dashboard:** Configure ground stations, target constellations, and link parameters via a dedicated MATLAB UI.
* **Live Orbital Data:** Integrates with the Space-Track.org API to pull fresh Two-Line Element (TLE) sets for active constellations.
* **3D Visualization:** Renders 2D mapping and 3D globe visualization of the calculated optical relay path.
* **Detailed Link Budgets:** Automatically computes per-hop received power, photon rates, SNR proxies, and Doppler shifts.

## Prerequisites
* **MATLAB 2025** (or newer)
* **Satellite Communications Toolbox**
* **Space-Track Account:** Required for pulling live TLE data. You must input your credentials into lines 17 & 18 of `FXN_download_tles_request.m`.

## Usage
1. Clone the repository.
2. Ensure `CatalogueOfCities.xlsx` and the constellation catalogs are in the working directory.
3. Run `RUN_MasterLinkDashboard_v2.m` in the MATLAB command window.
4. For detailed physics explanations and UI instructions, click the "User Manual" button in the dashboard or open `User Manual_OLSD.pdf`.

## License
Distributed under the MIT License. See `LICENSE` for more information.