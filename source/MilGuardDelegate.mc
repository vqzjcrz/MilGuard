import Toybox.Lang;
import Toybox.WatchUi;

class MilGuardDelegate extends WatchUi.BehaviorDelegate {

    private var _view as MilGuardView;

    function initialize(view as MilGuardView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // DOWN button, or swipe up on touchscreens
    function onNextPage() as Boolean {
        _view.nextPage();
        return true;
    }

    // UP button, or swipe down on touchscreens
    function onPreviousPage() as Boolean {
        _view.previousPage();
        return true;
    }

}
