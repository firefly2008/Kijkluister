# Plasma Bigscreen -> Windows: Fase 0 proof-of-concept skeleton
# Optie A (zie migratieplan): losse "Bigscreen Host" kiosk-app, geen KWin/Plasma-sessie.
#
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.24)
project(bigscreen-host LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 CONFIG REQUIRED COMPONENTS Core Gui Quick Qml Network)
qt_standard_project_setup(REQUIRES 6.8)
find_package(SDL3 CONFIG REQUIRED)

qt_add_executable(bigscreen-host WIN32
    src/main.cpp
    src/appmodel.cpp
    src/appmodel.h
    src/appiconprovider.cpp
    src/appiconprovider.h
    src/gamepadnavigator.cpp
    src/gamepadnavigator.h
    src/medialibrary.cpp
    src/medialibrary.h
)

if(WIN32)
    target_sources(bigscreen-host PRIVATE
        src/win32inputsystem.cpp
        src/win32inputsystem.h
    )
    target_compile_definitions(bigscreen-host PRIVATE BIGSCREEN_HAVE_WIN32_INPUT)
else()
    # Op Linux/macOS valt input-injectie voorlopig terug op een no-op stub,
    # zodat dit skeleton op elk platform blijft compileren tijdens de PoC-fase.
    target_sources(bigscreen-host PRIVATE
        src/noopinputsystem.cpp
        src/noopinputsystem.h
    )
endif()

# Zonder alias komt het bestand in de resources onder .../host/qml/Main.qml terecht
set(BIGSCREEN_QML_FILES qml/Main.qml qml/BannerTile.qml qml/QuickTile.qml qml/MenuOverlay.qml qml/AddTileOverlay.qml qml/LibraryScreen.qml qml/LibrarySetup.qml qml/FocusButton.qml qml/PosterTile.qml)
foreach(qml_file IN LISTS BIGSCREEN_QML_FILES)
    get_filename_component(qml_name ${qml_file} NAME)
    set_source_files_properties(${qml_file} PROPERTIES QT_RESOURCE_ALIAS ${qml_name})
endforeach()

qt_add_qml_module(bigscreen-host
    URI org.kde.plasma.bigscreen.host
    VERSION 1.0
    QML_FILES
        ${BIGSCREEN_QML_FILES}
)

target_link_libraries(bigscreen-host PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::Network
    SDL3::SDL3
)

if(WIN32)
    target_link_libraries(bigscreen-host PRIVATE user32 shell32 ole32 comctl32)
endif()

# Installatie: alles plat in een map, zodat windeployqt + Inno Setup er een installer van maken
install(TARGETS bigscreen-host RUNTIME DESTINATION .)
if(WIN32)
    install(FILES $<TARGET_RUNTIME_DLLS:bigscreen-host> DESTINATION .)
endif()

# --- Linux-only dependencies uit het origineel (plasma-bigscreen 6.8.2) ---
# Bewust NIET meegenomen in dit Windows-skeleton, zie het migratieplan (Architectuur-audit):
#   KF6 (BluezQt, DBusAddons, GlobalAccel, WindowSystem, KIO, ...), Plasma/PlasmaActivities,
#   LibKWorkspace, Qt6::WaylandClient, PlasmaWaylandProtocols, Wayland (pkg-config), systemd,
#   libcec (optioneel terug toe te voegen), QCoro6, Qt6::DBus, Qt6::WebEngineCore/Quick,
#   Qt6::Multimedia. Die laatste drie zijn wel kandidaten om in een volgende fase toe te voegen
#   (webapp-viewer, uvcviewer, audio-device-chooser) -- zie het migratieplan voor de volgorde.
