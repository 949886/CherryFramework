class_name NavigationDialog
extends NavigationPage

## Marker/base page for Dialog UI shown through [method Navigator.show_dialog]
## or [method Navigator.show_custom_dialog].
##
## Dialog is not a separate NavigationPage.Presentation. Every NavigationDialog
## is presented as MODAL, so it shares the normal route stack, lifecycle,
## PopScope, transition, result, and back behavior.
