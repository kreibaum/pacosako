module Svg.Github exposing (gitHubLogo)

import Element exposing (Element)
import Svg exposing (path, svg)
import Svg.Attributes as SvgAttr


gitHubLogo : Element msg
gitHubLogo =
    Element.html
        (svg
            [ SvgAttr.viewBox "0 1 44 44"
            ]
            [ path
                [ SvgAttr.d "M0 0c-33.347 0-60.388-27.035-60.388-60.388 0-26.68 17.303-49.316 41.297-57.301 3.018-.559 4.126 1.31 4.126 2.905 0 1.439-.056 6.197-.082 11.243-16.8-3.653-20.345 7.125-20.345 7.125-2.747 6.979-6.705 8.836-6.705 8.836-5.479 3.748.413 3.671.413 3.671 6.064-.426 9.257-6.224 9.257-6.224 5.386-9.231 14.127-6.562 17.573-5.019.543 3.902 2.107 6.567 3.834 8.075-13.413 1.526-27.513 6.705-27.513 29.844 0 6.592 2.359 11.98 6.222 16.209-.627 1.521-2.694 7.663.586 15.981 0 0 5.071 1.622 16.61-6.191 4.817 1.338 9.983 2.009 15.115 2.033 5.132-.024 10.302-.695 15.128-2.033 11.526 7.813 16.59 6.191 16.59 6.191 3.287-8.318 1.22-14.46.593-15.981 3.872-4.229 6.214-9.617 6.214-16.209 0-23.195-14.127-28.301-27.574-29.796 2.166-1.874 4.096-5.549 4.096-11.183 0-8.08-.069-14.583-.069-16.572 0-1.608 1.086-3.49 4.147-2.898 23.982 7.994 41.263 30.622 41.263 57.294C60.388-27.035 33.351 0 0 0"
                , SvgAttr.style "fill:#1b1817;fill-opacity:1;fill-rule:evenodd;stroke:none"
                , SvgAttr.transform "matrix(.35278 0 0 -.35278 22 1.223)"
                ]
                []
            , path
                [ SvgAttr.d "M0 0c-.133-.301-.605-.391-1.035-.185-.439.198-.684.607-.542.908.13.308.602.394 1.04.188C-.099.714.151.301 0 0"
                , SvgAttr.style "fill:#1b1817;fill-opacity:1;fill-rule:nonzero;stroke:none"
                , SvgAttr.transform "matrix(.35278 0 0 -.35278 8.765 31.81)"
                ]
                []
            , path
                [ SvgAttr.d "M0 0c-.288-.267-.852-.143-1.233.279-.396.421-.469.985-.177 1.255.297.267.843.142 1.238-.279C.224.829.301.271 0 0"
                , SvgAttr.style "fill:#1b1817;fill-opacity:1;fill-rule:nonzero;stroke:none"
                , SvgAttr.transform "matrix(.35278 0 0 -.35278 9.628 32.772)"
                ]
                []
            , path
                [ SvgAttr.d "M0 0c-.37-.258-.976-.017-1.35.52-.37.538-.37 1.182.009 1.44.374.258.971.025 1.35-.507C.378.907.378.263 0 0"
                , SvgAttr.style "fill:#1b1817;fill-opacity:1;fill-rule:nonzero;stroke:none"
                , SvgAttr.transform "matrix(.35278 0 0 -.35278 10.468 33.999)"
                ]
                []
            , path
                [ SvgAttr.d "M0 0c-.331-.365-1.036-.267-1.552.232-.528.486-.675 1.177-.344 1.542.336.366 1.045.263 1.565-.231C.193 1.057.352.361 0 0"
                , SvgAttr.style "fill:#1b1817;fill-opacity:1;fill-rule:nonzero;stroke:none"
                , SvgAttr.transform "matrix(.35278 0 0 -.35278 11.619 35.184)"
                ]
                []
            , path
                [ SvgAttr.d "M0 0c-.147-.473-.825-.687-1.509-.486-.683.207-1.13.76-.992 1.238.142.476.824.7 1.513.485C-.306 1.031.142.481 0 0"
                , SvgAttr.style "fill:#1b1817;fill-opacity:1;fill-rule:nonzero;stroke:none"
                , SvgAttr.transform "matrix(.35278 0 0 -.35278 13.206 35.873)"
                ]
                []
            , path
                [ SvgAttr.d "M0 0c.017-.498-.563-.911-1.281-.92-.722-.016-1.307.387-1.315.877 0 .503.568.911 1.289.924C-.589.895 0 .494 0 0"
                , SvgAttr.style "fill:#1b1817;fill-opacity:1;fill-rule:nonzero;stroke:none"
                , SvgAttr.transform "matrix(.35278 0 0 -.35278 14.95 36)"
                ]
                []
            , path
                [ SvgAttr.d "M0 0c.086-.485-.413-.984-1.126-1.117-.701-.129-1.35.172-1.439.653-.087.498.42.997 1.121 1.126C-.73.786-.091.494 0 0"
                , SvgAttr.style "fill:#1b1817;fill-opacity:1;fill-rule:nonzero;stroke:none"
                , SvgAttr.transform "matrix(.35278 0 0 -.35278 16.572 35.724)"
                ]
                []
            ]
        )
