angular.module("beamng.apps").directive("taxiDriverHud", [
  function () {
    return {
      templateUrl: "/ui/modules/apps/TaxiDriverHUD/app.html",
      replace: false,
      restrict: "E",
      scope: true,
      controllerAs: "hud",
      controller: function ($scope, $element) {
        const i18n = {
          en: {
            appSubtitle: "Driver app", online: "online", settingsTitle: "Settings", language: "Language", languageHelp: "English is used by default on every new installation.", rememberLanguage: "Remember selected language", fontSize: "Text size", fontSizeHelp: "Increase text without resizing the phone.", difficulty: "Violation difficulty", difficultyHelp: "Controls tolerances and how quickly fare penalties accumulate.", routeGuidance: "Road guidance", routeGuidanceHelp: "Show navigation arrows directly on the road. The route remains visible on the map.", silentMode: "Silent mode", silentModeHelp: "Disable the short notification sound for new violations.", save: "SAVE SETTINGS", settingsSaved: "Settings saved", minimize: "Minimize", expand: "Open phone", nextOfferTitle: "Next ride", nextOfferDesc: "Accept before the current ride ends", offerExpires: "Offer expires in {time}", nextOfferAccepted: "NEXT RIDE ACCEPTED",
            homeTitle: "Ready for orders?", homeDesc: "The app will find passengers on the road network and build routes automatically.", start: "START DRIVING", balance: "Balance", rides: "Rides", rating: "Rating",
            chooseOrder: "Choose an order", searchOrders: "Searching for orders", connecting: "Connecting to the dispatch line", emptyOffers: "Connecting and looking for nearby passengers. Offers will appear gradually.", toPassenger: "Passenger pickup", trip: "Trip", distance: "Distance", payment: "Fare", rushDeliver: "Rush: deliver within {time}", bonus: "bonus", accept: "ACCEPT ORDER", offers: "{count} of {target} offers", offline: "GO OFFLINE",
            boardingDesc: "The passenger is taking a seat. Wait for the door to close.", alightingDesc: "The passenger is leaving the vehicle. Finishing the ride.", complete: "Ride completed", completeDesc: "Rating {rating} / 5.00 · the next offer will appear automatically.",
            arrival: "Arrival", followRoute: "Follow the highlighted route", rushLost: "Bonus lost", rushBonus: "Rush order · bonus {amount}", payout: "Payout", estimate: "Estimate", reduction: "Reduction", penaltyEvents: "Fare reduction events", noViolations: "No violations recorded", yourRating: "Your rating", finish: "FINISH",
            notify_orderAccepted: "Order for {name} accepted", notify_passengerAboard: "Passenger aboard. Continue to the destination.", notify_rideComplete: "Ride completed · payout {fare}", notify_rushExpired: "Rush bonus expired. Base fare is preserved.", notify_modeStopped: "Taxi mode stopped", notify_vehicleChanged: "Taxi mode stopped after changing vehicle", notify_vehicleReset: "Taxi mode stopped after resetting vehicle", notify_orderUnavailable: "The order is no longer available", notify_nextUnavailable: "The queued order is no longer available", notify_noVehicle: "Select a vehicle first", notify_noRoadGraph: "This map has no usable road network",
            phase_inactive: "Taxi mode is off", phase_searching: "Searching for orders", phase_toPickup: "Drive to the passenger", phase_boarding: "Passenger is boarding", phase_toDestination: "Drive to destination", phase_alighting: "Passenger is leaving", phase_complete: "Ride completed", phase_error: "Order unavailable",
            progress_route: "Route", progress_pickup: "To passenger", progress_ride: "Trip progress", progress_boarding: "Boarding", progress_alighting: "Drop-off",
            penalty_speeding: "Speeding", penalty_collision: "Collision", penalty_aggression: "Harsh manoeuvre", penalty_bonus: "Rush bonus lost", detail_speeding: "+{speed} km/h · {duration} s", detail_collision: "Vehicle damage +{damage}", detail_aggression: "Peak load {g} g", detail_bonus: "The order time limit expired",
            unitMin: "min", unitHour: "h", unitMeter: "m", unitKm: "km",
            difficulty_elementary: "Elementary", difficulty_easy: "Easy", difficulty_standard: "Standard", difficulty_professional: "Professional",
            desc_elementary: "Large tolerances; only serious or sustained violations matter.", desc_easy: "Forgiving city driving with mild penalties.", desc_standard: "Balanced rules for attentive driving.", desc_professional: "Strict tolerances and fast penalty accumulation."
          },
          ru: {
            appSubtitle: "Приложение водителя", online: "на линии", settingsTitle: "Настройки", language: "Язык", languageHelp: "При первой установке используется английский язык.", rememberLanguage: "Запомнить выбранный язык", fontSize: "Размер текста", fontSizeHelp: "Увеличивает текст без изменения размера телефона.", difficulty: "Сложность нарушений", difficultyHelp: "Определяет допуски и скорость снижения оплаты.", routeGuidance: "Траектория на дороге", routeGuidanceHelp: "Показывает навигационные стрелки поверх дороги. Маршрут на карте останется видимым.", silentMode: "Беззвучный режим", silentModeHelp: "Отключает короткий звук уведомления о новых нарушениях.", save: "СОХРАНИТЬ НАСТРОЙКИ", settingsSaved: "Настройки сохранены", minimize: "Свернуть", expand: "Развернуть", nextOfferTitle: "Следующая поездка", nextOfferDesc: "Можно принять до завершения текущей поездки", offerExpires: "Предложение исчезнет через {time}", nextOfferAccepted: "СЛЕДУЮЩИЙ ЗАКАЗ ПРИНЯТ",
            homeTitle: "Готовы к заказам?", homeDesc: "Приложение найдёт пассажиров на дорожной сети и автоматически построит маршрут.", start: "НАЧАТЬ ПОЕЗДКУ", balance: "Баланс", rides: "Поездок", rating: "Рейтинг",
            chooseOrder: "Выберите заказ", searchOrders: "Поиск заказов", connecting: "Подключение к линии заказов", emptyOffers: "Ищем пассажиров поблизости. Предложения будут появляться постепенно.", toPassenger: "До пассажира", trip: "Поездка", distance: "Расстояние", payment: "Оплата", rushDeliver: "Срочный: доставить за {time}", bonus: "бонус", accept: "ПРИНЯТЬ ЗАКАЗ", offers: "{count} из {target} предложений", offline: "УЙТИ С ЛИНИИ",
            boardingDesc: "Пассажир занимает место. Дождитесь закрытия двери.", alightingDesc: "Пассажир покидает автомобиль. Завершаем поездку.", complete: "Поездка завершена", completeDesc: "Рейтинг {rating} / 5.00 · следующий заказ появится автоматически.",
            arrival: "Прибытие", followRoute: "Следуйте по отмеченному маршруту", rushLost: "Бонус отменён", rushBonus: "Срочный заказ · бонус {amount}", payout: "К выплате", estimate: "Расчёт", reduction: "Снижение", penaltyEvents: "События снижения оплаты", noViolations: "Нарушений не зафиксировано", yourRating: "Ваш рейтинг", finish: "ЗАВЕРШИТЬ",
            notify_orderAccepted: "Заказ для {name} принят", notify_passengerAboard: "Пассажир в автомобиле. Следуйте к месту назначения.", notify_rideComplete: "Поездка завершена · выплата {fare}", notify_rushExpired: "Срок бонуса истёк. Базовая оплата сохранена.", notify_modeStopped: "Режим такси завершён", notify_vehicleChanged: "Режим остановлен после смены автомобиля", notify_vehicleReset: "Режим остановлен после сброса автомобиля", notify_orderUnavailable: "Заказ больше недоступен", notify_nextUnavailable: "Заказ в очереди больше недоступен", notify_noVehicle: "Сначала выберите автомобиль", notify_noRoadGraph: "На карте отсутствует подходящая дорожная сеть",
            phase_inactive: "Режим такси выключен", phase_searching: "Поиск заказов", phase_toPickup: "Следуйте к пассажиру", phase_boarding: "Пассажир садится", phase_toDestination: "Доставьте пассажира", phase_alighting: "Пассажир выходит", phase_complete: "Поездка завершена", phase_error: "Заказ недоступен",
            progress_route: "Маршрут", progress_pickup: "До пассажира", progress_ride: "Прогресс поездки", progress_boarding: "Посадка", progress_alighting: "Высадка",
            penalty_speeding: "Превышение скорости", penalty_collision: "Столкновение", penalty_aggression: "Резкий манёвр", penalty_bonus: "Бонус за срочность отменён", detail_speeding: "+{speed} км/ч · {duration} с", detail_collision: "Повреждение автомобиля +{damage}", detail_aggression: "Пиковая нагрузка {g} g", detail_bonus: "Истёк лимит времени заказа",
            unitMin: "мин", unitHour: "ч", unitMeter: "м", unitKm: "км",
            difficulty_elementary: "Элементарный", difficulty_easy: "Лёгкий", difficulty_standard: "Стандартный", difficulty_professional: "Профессиональный",
            desc_elementary: "Большие допуски: учитываются только серьёзные нарушения.", desc_easy: "Мягкие правила для спокойной городской езды.", desc_standard: "Сбалансированные требования к внимательному водителю.", desc_professional: "Строгие допуски и быстрое накопление штрафов."
          },
          de: {
            appSubtitle: "Fahrer-App", online: "online", settingsTitle: "Einstellungen", language: "Sprache", languageHelp: "Englisch wird bei einer neuen Installation standardmäßig verwendet.", rememberLanguage: "Ausgewählte Sprache speichern", fontSize: "Textgröße", fontSizeHelp: "Vergrößert Text, ohne das Telefon zu skalieren.", difficulty: "Verstoß-Schwierigkeit", difficultyHelp: "Bestimmt Toleranzen und die Höhe der Fahrpreisabzüge.", routeGuidance: "Straßennavigation", routeGuidanceHelp: "Zeigt Navigationspfeile direkt auf der Straße. Die Route bleibt auf der Karte sichtbar.", silentMode: "Lautlosmodus", silentModeHelp: "Deaktiviert den kurzen Hinweiston bei neuen Verstößen.", save: "EINSTELLUNGEN SPEICHERN", settingsSaved: "Einstellungen gespeichert", minimize: "Einklappen", expand: "Telefon öffnen", nextOfferTitle: "Nächste Fahrt", nextOfferDesc: "Vor Ende der aktuellen Fahrt annehmen", offerExpires: "Angebot endet in {time}", nextOfferAccepted: "NÄCHSTE FAHRT ANGENOMMEN",
            homeTitle: "Bereit für Aufträge?", homeDesc: "Die App findet Fahrgäste im Straßennetz und erstellt automatisch Routen.", start: "FAHRT STARTEN", balance: "Guthaben", rides: "Fahrten", rating: "Bewertung",
            chooseOrder: "Auftrag auswählen", searchOrders: "Auftragssuche", connecting: "Verbindung zur Zentrale", emptyOffers: "Fahrgäste in der Nähe werden gesucht. Angebote erscheinen nach und nach.", toPassenger: "Zum Fahrgast", trip: "Fahrt", distance: "Strecke", payment: "Vergütung", rushDeliver: "Eilauftrag: innerhalb {time}", bonus: "Bonus", accept: "AUFTRAG ANNEHMEN", offers: "{count} von {target} Angeboten", offline: "OFFLINE GEHEN",
            boardingDesc: "Der Fahrgast steigt ein. Warten Sie, bis die Tür geschlossen ist.", alightingDesc: "Der Fahrgast steigt aus. Die Fahrt wird beendet.", complete: "Fahrt abgeschlossen", completeDesc: "Bewertung {rating} / 5.00 · der nächste Auftrag erscheint automatisch.", arrival: "Ankunft", followRoute: "Folgen Sie der markierten Route", rushLost: "Bonus verloren", rushBonus: "Eilauftrag · Bonus {amount}", payout: "Auszahlung", estimate: "Schätzung", reduction: "Abzug", penaltyEvents: "Ereignisse mit Fahrpreisabzug", noViolations: "Keine Verstöße erfasst", yourRating: "Ihre Bewertung", finish: "BEENDEN",
            notify_orderAccepted: "Auftrag für {name} angenommen", notify_passengerAboard: "Fahrgast an Bord. Fahren Sie zum Ziel.", notify_rideComplete: "Fahrt beendet · Auszahlung {fare}", notify_rushExpired: "Eilbonus abgelaufen. Grundpreis bleibt erhalten.", notify_modeStopped: "Taximodus beendet", notify_vehicleChanged: "Taximodus nach Fahrzeugwechsel beendet", notify_vehicleReset: "Taximodus nach Fahrzeugrücksetzung beendet", notify_orderUnavailable: "Auftrag nicht mehr verfügbar", notify_nextUnavailable: "Vorgemerkter Auftrag nicht mehr verfügbar", notify_noVehicle: "Wählen Sie zuerst ein Fahrzeug", notify_noRoadGraph: "Diese Karte hat kein nutzbares Straßennetz",
            phase_inactive: "Taximodus aus", phase_searching: "Auftragssuche", phase_toPickup: "Zum Fahrgast fahren", phase_boarding: "Fahrgast steigt ein", phase_toDestination: "Zum Ziel fahren", phase_alighting: "Fahrgast steigt aus", phase_complete: "Fahrt abgeschlossen", phase_error: "Auftrag nicht verfügbar",
            progress_route: "Route", progress_pickup: "Zum Fahrgast", progress_ride: "Fahrtfortschritt", progress_boarding: "Einstieg", progress_alighting: "Ausstieg",
            penalty_speeding: "Geschwindigkeitsüberschreitung", penalty_collision: "Kollision", penalty_aggression: "Abruptes Manöver", penalty_bonus: "Eilbonus verloren", detail_speeding: "+{speed} km/h · {duration} s", detail_collision: "Fahrzeugschaden +{damage}", detail_aggression: "Spitzenbelastung {g} g", detail_bonus: "Zeitlimit des Auftrags abgelaufen", unitMin: "Min.", unitHour: "Std.", unitMeter: "m", unitKm: "km",
            difficulty_elementary: "Elementar", difficulty_easy: "Einfach", difficulty_standard: "Standard", difficulty_professional: "Professionell", desc_elementary: "Große Toleranzen; nur schwere Verstöße zählen.", desc_easy: "Nachsichtige Regeln und geringe Abzüge.", desc_standard: "Ausgewogene Regeln für aufmerksames Fahren.", desc_professional: "Strenge Toleranzen und schnelle Abzüge."
          },
          fr: {
            appSubtitle: "Application chauffeur", online: "en ligne", settingsTitle: "Paramètres", language: "Langue", languageHelp: "L’anglais est utilisé par défaut après l’installation.", rememberLanguage: "Mémoriser la langue choisie", fontSize: "Taille du texte", fontSizeHelp: "Agrandit le texte sans redimensionner le téléphone.", difficulty: "Difficulté des infractions", difficultyHelp: "Définit les tolérances et la vitesse de réduction du tarif.", routeGuidance: "Guidage sur la route", routeGuidanceHelp: "Affiche les flèches de navigation sur la chaussée. L’itinéraire reste visible sur la carte.", silentMode: "Mode silencieux", silentModeHelp: "Désactive le bref son des nouvelles infractions.", save: "ENREGISTRER", settingsSaved: "Paramètres enregistrés", minimize: "Réduire", expand: "Ouvrir le téléphone", nextOfferTitle: "Prochaine course", nextOfferDesc: "Acceptez avant la fin de la course actuelle", offerExpires: "L’offre expire dans {time}", nextOfferAccepted: "PROCHAINE COURSE ACCEPTÉE",
            homeTitle: "Prêt à recevoir des courses ?", homeDesc: "L’application trouvera des passagers sur le réseau routier et créera les itinéraires.", start: "COMMENCER", balance: "Solde", rides: "Courses", rating: "Note",
            chooseOrder: "Choisir une course", searchOrders: "Recherche de courses", connecting: "Connexion à la centrale", emptyOffers: "Recherche de passagers à proximité. Les offres apparaîtront progressivement.", toPassenger: "Vers le passager", trip: "Course", distance: "Distance", payment: "Paiement", rushDeliver: "Urgent : livrer en {time}", bonus: "bonus", accept: "ACCEPTER", offers: "{count} offres sur {target}", offline: "SE DÉCONNECTER",
            boardingDesc: "Le passager s’installe. Attendez la fermeture de la porte.", alightingDesc: "Le passager quitte le véhicule. Fin de la course.", complete: "Course terminée", completeDesc: "Note {rating} / 5.00 · la prochaine offre apparaîtra automatiquement.", arrival: "Arrivée", followRoute: "Suivez l’itinéraire indiqué", rushLost: "Bonus perdu", rushBonus: "Course urgente · bonus {amount}", payout: "À payer", estimate: "Estimation", reduction: "Réduction", penaltyEvents: "Événements réduisant le tarif", noViolations: "Aucune infraction enregistrée", yourRating: "Votre note", finish: "TERMINER",
            notify_orderAccepted: "Course pour {name} acceptée", notify_passengerAboard: "Passager à bord. Continuez vers la destination.", notify_rideComplete: "Course terminée · paiement {fare}", notify_rushExpired: "Bonus urgent expiré. Le tarif de base est conservé.", notify_modeStopped: "Mode taxi arrêté", notify_vehicleChanged: "Mode taxi arrêté après changement de véhicule", notify_vehicleReset: "Mode taxi arrêté après réinitialisation du véhicule", notify_orderUnavailable: "Course indisponible", notify_nextUnavailable: "Course en attente indisponible", notify_noVehicle: "Sélectionnez d’abord un véhicule", notify_noRoadGraph: "Cette carte ne possède pas de réseau routier utilisable",
            phase_inactive: "Mode taxi désactivé", phase_searching: "Recherche de courses", phase_toPickup: "Rejoignez le passager", phase_boarding: "Le passager monte", phase_toDestination: "Conduisez à destination", phase_alighting: "Le passager descend", phase_complete: "Course terminée", phase_error: "Course indisponible",
            progress_route: "Itinéraire", progress_pickup: "Vers le passager", progress_ride: "Progression", progress_boarding: "Embarquement", progress_alighting: "Dépose",
            penalty_speeding: "Excès de vitesse", penalty_collision: "Collision", penalty_aggression: "Manœuvre brusque", penalty_bonus: "Bonus urgent perdu", detail_speeding: "+{speed} km/h · {duration} s", detail_collision: "Dégâts au véhicule +{damage}", detail_aggression: "Charge maximale {g} g", detail_bonus: "Délai de la course dépassé", unitMin: "min", unitHour: "h", unitMeter: "m", unitKm: "km",
            difficulty_elementary: "Élémentaire", difficulty_easy: "Facile", difficulty_standard: "Standard", difficulty_professional: "Professionnel", desc_elementary: "Tolérances élevées, seules les infractions graves comptent.", desc_easy: "Règles souples et faibles pénalités.", desc_standard: "Règles équilibrées pour une conduite attentive.", desc_professional: "Tolérances strictes et pénalités rapides."
          },
          es: {
            appSubtitle: "Aplicación del conductor", online: "en línea", settingsTitle: "Ajustes", language: "Idioma", languageHelp: "El inglés se usa de forma predeterminada tras la instalación.", rememberLanguage: "Recordar el idioma seleccionado", fontSize: "Tamaño del texto", fontSizeHelp: "Aumenta el texto sin cambiar el tamaño del teléfono.", difficulty: "Dificultad de infracciones", difficultyHelp: "Controla las tolerancias y la rapidez de las reducciones.", routeGuidance: "Guía sobre la carretera", routeGuidanceHelp: "Muestra flechas de navegación sobre la carretera. La ruta seguirá visible en el mapa.", silentMode: "Modo silencioso", silentModeHelp: "Desactiva el breve sonido de las nuevas infracciones.", save: "GUARDAR AJUSTES", settingsSaved: "Ajustes guardados", minimize: "Minimizar", expand: "Abrir teléfono", nextOfferTitle: "Siguiente viaje", nextOfferDesc: "Acepta antes de terminar el viaje actual", offerExpires: "La oferta caduca en {time}", nextOfferAccepted: "SIGUIENTE VIAJE ACEPTADO",
            homeTitle: "¿Listo para recibir viajes?", homeDesc: "La aplicación buscará pasajeros en la red vial y creará las rutas automáticamente.", start: "EMPEZAR A CONDUCIR", balance: "Saldo", rides: "Viajes", rating: "Valoración",
            chooseOrder: "Elegir un viaje", searchOrders: "Buscando viajes", connecting: "Conectando con la central", emptyOffers: "Buscando pasajeros cercanos. Las ofertas aparecerán poco a poco.", toPassenger: "Hasta el pasajero", trip: "Viaje", distance: "Distancia", payment: "Pago", rushDeliver: "Urgente: completar en {time}", bonus: "bono", accept: "ACEPTAR VIAJE", offers: "{count} de {target} ofertas", offline: "DESCONECTARSE",
            boardingDesc: "El pasajero está subiendo. Espera a que se cierre la puerta.", alightingDesc: "El pasajero está bajando. Finalizando el viaje.", complete: "Viaje completado", completeDesc: "Valoración {rating} / 5.00 · la siguiente oferta aparecerá automáticamente.", arrival: "Llegada", followRoute: "Sigue la ruta indicada", rushLost: "Bono perdido", rushBonus: "Viaje urgente · bono {amount}", payout: "A cobrar", estimate: "Estimado", reduction: "Reducción", penaltyEvents: "Eventos que reducen el pago", noViolations: "No se registraron infracciones", yourRating: "Tu valoración", finish: "FINALIZAR",
            notify_orderAccepted: "Viaje para {name} aceptado", notify_passengerAboard: "Pasajero a bordo. Continúa al destino.", notify_rideComplete: "Viaje completado · pago {fare}", notify_rushExpired: "El bono urgente ha caducado. Se conserva la tarifa base.", notify_modeStopped: "Modo taxi detenido", notify_vehicleChanged: "Modo taxi detenido tras cambiar de vehículo", notify_vehicleReset: "Modo taxi detenido tras reiniciar el vehículo", notify_orderUnavailable: "El viaje ya no está disponible", notify_nextUnavailable: "El viaje en cola ya no está disponible", notify_noVehicle: "Selecciona primero un vehículo", notify_noRoadGraph: "Este mapa no tiene una red vial utilizable",
            phase_inactive: "Modo taxi desactivado", phase_searching: "Buscando viajes", phase_toPickup: "Ve al pasajero", phase_boarding: "El pasajero está subiendo", phase_toDestination: "Conduce al destino", phase_alighting: "El pasajero está bajando", phase_complete: "Viaje completado", phase_error: "Viaje no disponible",
            progress_route: "Ruta", progress_pickup: "Hasta el pasajero", progress_ride: "Progreso del viaje", progress_boarding: "Recogida", progress_alighting: "Bajada",
            penalty_speeding: "Exceso de velocidad", penalty_collision: "Colisión", penalty_aggression: "Maniobra brusca", penalty_bonus: "Bono urgente perdido", detail_speeding: "+{speed} km/h · {duration} s", detail_collision: "Daño del vehículo +{damage}", detail_aggression: "Carga máxima {g} g", detail_bonus: "Se agotó el tiempo del viaje", unitMin: "min", unitHour: "h", unitMeter: "m", unitKm: "km",
            difficulty_elementary: "Elemental", difficulty_easy: "Fácil", difficulty_standard: "Estándar", difficulty_professional: "Profesional", desc_elementary: "Amplias tolerancias; solo cuentan infracciones graves.", desc_easy: "Reglas permisivas y penalizaciones leves.", desc_standard: "Reglas equilibradas para conducción atenta.", desc_professional: "Tolerancias estrictas y penalizaciones rápidas."
          },
          pl: {
            appSubtitle: "Aplikacja kierowcy", online: "online", settingsTitle: "Ustawienia", language: "Język", languageHelp: "Po instalacji domyślnie używany jest język angielski.", rememberLanguage: "Zapamiętaj wybrany język", fontSize: "Rozmiar tekstu", fontSizeHelp: "Powiększa tekst bez zmiany rozmiaru telefonu.", difficulty: "Poziom wykroczeń", difficultyHelp: "Określa tolerancje i tempo obniżania zapłaty.", routeGuidance: "Nawigacja na drodze", routeGuidanceHelp: "Pokazuje strzałki nawigacji na jezdni. Trasa pozostaje widoczna na mapie.", silentMode: "Tryb cichy", silentModeHelp: "Wyłącza krótki dźwięk nowych wykroczeń.", save: "ZAPISZ USTAWIENIA", settingsSaved: "Ustawienia zapisane", minimize: "Zwiń", expand: "Otwórz telefon", nextOfferTitle: "Następny kurs", nextOfferDesc: "Przyjmij przed końcem bieżącego kursu", offerExpires: "Oferta wygaśnie za {time}", nextOfferAccepted: "NASTĘPNY KURS PRZYJĘTY",
            homeTitle: "Gotowy na zlecenia?", homeDesc: "Aplikacja znajdzie pasażerów na sieci drogowej i automatycznie wyznaczy trasy.", start: "ROZPOCZNIJ JAZDĘ", balance: "Saldo", rides: "Kursy", rating: "Ocena",
            chooseOrder: "Wybierz zlecenie", searchOrders: "Szukanie zleceń", connecting: "Łączenie z centralą", emptyOffers: "Szukamy pasażerów w pobliżu. Oferty będą pojawiać się stopniowo.", toPassenger: "Do pasażera", trip: "Kurs", distance: "Dystans", payment: "Zapłata", rushDeliver: "Pilne: dostarcz w {time}", bonus: "premia", accept: "PRZYJMIJ ZLECENIE", offers: "{count} z {target} ofert", offline: "ZEJDŹ Z LINII",
            boardingDesc: "Pasażer zajmuje miejsce. Poczekaj na zamknięcie drzwi.", alightingDesc: "Pasażer opuszcza pojazd. Kończenie kursu.", complete: "Kurs zakończony", completeDesc: "Ocena {rating} / 5.00 · następna oferta pojawi się automatycznie.", arrival: "Przyjazd", followRoute: "Jedź wyznaczoną trasą", rushLost: "Premia utracona", rushBonus: "Pilny kurs · premia {amount}", payout: "Do wypłaty", estimate: "Wycena", reduction: "Obniżka", penaltyEvents: "Zdarzenia obniżające zapłatę", noViolations: "Nie odnotowano wykroczeń", yourRating: "Twoja ocena", finish: "ZAKOŃCZ",
            notify_orderAccepted: "Przyjęto kurs dla {name}", notify_passengerAboard: "Pasażer w pojeździe. Jedź do celu.", notify_rideComplete: "Kurs zakończony · wypłata {fare}", notify_rushExpired: "Premia za pośpiech wygasła. Zachowano stawkę podstawową.", notify_modeStopped: "Tryb taksówki zakończony", notify_vehicleChanged: "Tryb taksówki zakończony po zmianie pojazdu", notify_vehicleReset: "Tryb taksówki zakończony po zresetowaniu pojazdu", notify_orderUnavailable: "Zlecenie nie jest już dostępne", notify_nextUnavailable: "Zlecenie w kolejce nie jest już dostępne", notify_noVehicle: "Najpierw wybierz pojazd", notify_noRoadGraph: "Ta mapa nie ma użytecznej sieci drogowej",
            phase_inactive: "Tryb taksówki wyłączony", phase_searching: "Szukanie zleceń", phase_toPickup: "Jedź do pasażera", phase_boarding: "Pasażer wsiada", phase_toDestination: "Jedź do celu", phase_alighting: "Pasażer wysiada", phase_complete: "Kurs zakończony", phase_error: "Zlecenie niedostępne",
            progress_route: "Trasa", progress_pickup: "Do pasażera", progress_ride: "Postęp kursu", progress_boarding: "Wsiadanie", progress_alighting: "Wysiadanie",
            penalty_speeding: "Przekroczenie prędkości", penalty_collision: "Kolizja", penalty_aggression: "Gwałtowny manewr", penalty_bonus: "Utrata premii", detail_speeding: "+{speed} km/h · {duration} s", detail_collision: "Uszkodzenie pojazdu +{damage}", detail_aggression: "Maksymalne przeciążenie {g} g", detail_bonus: "Upłynął limit czasu", unitMin: "min", unitHour: "godz.", unitMeter: "m", unitKm: "km",
            difficulty_elementary: "Elementarny", difficulty_easy: "Łatwy", difficulty_standard: "Standardowy", difficulty_professional: "Profesjonalny", desc_elementary: "Duże tolerancje; liczą się tylko poważne wykroczenia.", desc_easy: "Łagodne zasady i niewielkie potrącenia.", desc_standard: "Zrównoważone zasady uważnej jazdy.", desc_professional: "Ścisłe tolerancje i szybkie potrącenia."
          },
          uk: {
            appSubtitle: "Застосунок водія", online: "на лінії", settingsTitle: "Налаштування", language: "Мова", languageHelp: "Після встановлення типово використовується англійська мова.", rememberLanguage: "Запам’ятати вибрану мову", fontSize: "Розмір тексту", fontSizeHelp: "Збільшує текст без зміни розміру телефона.", difficulty: "Складність порушень", difficultyHelp: "Визначає допуски та швидкість зниження оплати.", routeGuidance: "Траєкторія на дорозі", routeGuidanceHelp: "Показує навігаційні стрілки поверх дороги. Маршрут на карті залишиться видимим.", silentMode: "Беззвучний режим", silentModeHelp: "Вимикає короткий звук нових порушень.", save: "ЗБЕРЕГТИ НАЛАШТУВАННЯ", settingsSaved: "Налаштування збережено", minimize: "Згорнути", expand: "Розгорнути", nextOfferTitle: "Наступна поїздка", nextOfferDesc: "Прийміть до завершення поточної поїздки", offerExpires: "Пропозиція зникне через {time}", nextOfferAccepted: "НАСТУПНЕ ЗАМОВЛЕННЯ ПРИЙНЯТО",
            homeTitle: "Готові до замовлень?", homeDesc: "Застосунок знайде пасажирів на дорожній мережі та автоматично побудує маршрути.", start: "ПОЧАТИ РОБОТУ", balance: "Баланс", rides: "Поїздок", rating: "Рейтинг",
            chooseOrder: "Оберіть замовлення", searchOrders: "Пошук замовлень", connecting: "Підключення до лінії", emptyOffers: "Шукаємо пасажирів поблизу. Пропозиції з’являтимуться поступово.", toPassenger: "До пасажира", trip: "Поїздка", distance: "Відстань", payment: "Оплата", rushDeliver: "Термінове: доставити за {time}", bonus: "бонус", accept: "ПРИЙНЯТИ ЗАМОВЛЕННЯ", offers: "{count} із {target} пропозицій", offline: "ПІТИ З ЛІНІЇ",
            boardingDesc: "Пасажир займає місце. Дочекайтеся закриття дверей.", alightingDesc: "Пасажир залишає автомобіль. Завершуємо поїздку.", complete: "Поїздку завершено", completeDesc: "Рейтинг {rating} / 5.00 · наступне замовлення з’явиться автоматично.", arrival: "Прибуття", followRoute: "Рухайтеся позначеним маршрутом", rushLost: "Бонус скасовано", rushBonus: "Термінове замовлення · бонус {amount}", payout: "До виплати", estimate: "Розрахунок", reduction: "Зниження", penaltyEvents: "Події зниження оплати", noViolations: "Порушень не зафіксовано", yourRating: "Ваш рейтинг", finish: "ЗАВЕРШИТИ",
            notify_orderAccepted: "Замовлення для {name} прийнято", notify_passengerAboard: "Пасажир в автомобілі. Прямуйте до місця призначення.", notify_rideComplete: "Поїздку завершено · виплата {fare}", notify_rushExpired: "Термін бонусу минув. Базову оплату збережено.", notify_modeStopped: "Режим таксі завершено", notify_vehicleChanged: "Режим зупинено після зміни автомобіля", notify_vehicleReset: "Режим зупинено після скидання автомобіля", notify_orderUnavailable: "Замовлення більше недоступне", notify_nextUnavailable: "Замовлення в черзі більше недоступне", notify_noVehicle: "Спочатку виберіть автомобіль", notify_noRoadGraph: "На цій карті немає придатної дорожньої мережі",
            phase_inactive: "Режим таксі вимкнено", phase_searching: "Пошук замовлень", phase_toPickup: "Їдьте до пасажира", phase_boarding: "Пасажир сідає", phase_toDestination: "Доставте пасажира", phase_alighting: "Пасажир виходить", phase_complete: "Поїздку завершено", phase_error: "Замовлення недоступне",
            progress_route: "Маршрут", progress_pickup: "До пасажира", progress_ride: "Прогрес поїздки", progress_boarding: "Посадка", progress_alighting: "Висадка",
            penalty_speeding: "Перевищення швидкості", penalty_collision: "Зіткнення", penalty_aggression: "Різкий маневр", penalty_bonus: "Бонус за терміновість скасовано", detail_speeding: "+{speed} км/год · {duration} с", detail_collision: "Пошкодження автомобіля +{damage}", detail_aggression: "Пікове навантаження {g} g", detail_bonus: "Сплив ліміт часу замовлення", unitMin: "хв", unitHour: "год", unitMeter: "м", unitKm: "км",
            difficulty_elementary: "Елементарний", difficulty_easy: "Легкий", difficulty_standard: "Стандартний", difficulty_professional: "Професійний", desc_elementary: "Великі допуски; враховуються лише серйозні порушення.", desc_easy: "М’які правила та невеликі штрафи.", desc_standard: "Збалансовані правила для уважного водія.", desc_professional: "Суворі допуски та швидке накопичення штрафів."
          }
        };

        const featureI18n = {
          en: {
            silentModeHelp: "Disable all TaxiDriver app sounds.",
            passengerCalmness: "Passenger calmness", stopDemandTitle: "Passenger wants to get out", stopDemandDesc: "The vehicle is stopping safely. Controls are temporarily locked.", forcedExitTitle: "Passenger is leaving", forcedExitDesc: "The passenger ended the ride early. Wait for the door to close.", ratingLoss: "Driver rating −{percent}%", phase_passengerStopDemand: "Passenger demands a stop", phase_passengerForcedExit: "Passenger is leaving early",
            penaltyEvents: "Penalties", noViolations: "No penalties",
            multiStopBadge: "STOPS ×{count}",
            dashCalm: "Calm", dashPickup: "Pickup", dashStop: "Stop", dashRush: "Rush", dashRating: "Rating", dashLost: "Lost",
            offersDynamic: "{count} of {target} offers", pickupWindow: "Pickup within {time}", pickupDeadline: "Pickup countdown", pickupLate: "Passenger waiting · late by {time}",
            ratingBonusLine: "Driver rating bonus +{percent}% · +{amount}", multiStopRide: "Ride with stops", multiStopSummary: "{count} stops · {time} at each stop", stopProgress: "Stop {current} of {total}",
            stopWaitingDesc: "Remain stopped for 10 seconds. Moving away restarts the timer.", phase_toStop: "Drive to the next stop", phase_stopWaiting: "Waiting at the stop", progress_stop: "To the next stop", progress_stopWaiting: "Stop in progress",
            penalty_pickupDelay: "Late passenger pickup", detail_pickupDelay: "Pickup deadline exceeded by {time}", notify_pickupLate: "Pickup deadline missed. The fare is now reduced.", notify_multiStopStarted: "Passenger aboard · {count} scheduled stops", notify_stopComplete: "Stop completed. Continue the ride."
          },
          ru: {
            silentModeHelp: "Отключает все звуки приложения TaxiDriver.",
            passengerCalmness: "Спокойствие пассажира", stopDemandTitle: "Пассажир требует остановиться", stopDemandDesc: "Автомобиль безопасно останавливается. Управление временно заблокировано.", forcedExitTitle: "Пассажир выходит", forcedExitDesc: "Пассажир досрочно завершил поездку. Дождитесь закрытия двери.", ratingLoss: "Рейтинг водителя −{percent}%", phase_passengerStopDemand: "Пассажир требует остановиться", phase_passengerForcedExit: "Пассажир досрочно выходит",
            penaltyEvents: "Штрафы", noViolations: "Штрафов нет",
            multiStopBadge: "ОСТАНОВКИ ×{count}",
            dashCalm: "Покой", dashPickup: "Подача", dashStop: "Стоп", dashRush: "Срочно", dashRating: "Рейтинг", dashLost: "Снят",
            offersDynamic: "{count} из {target} предложений", pickupWindow: "Подать машину за {time}", pickupDeadline: "Срок подачи", pickupLate: "Пассажир ждёт · опоздание {time}",
            ratingBonusLine: "Бонус за рейтинг +{percent}% · +{amount}", multiStopRide: "Поездка с остановками", multiStopSummary: "Остановок: {count} · по {time} на каждой", stopProgress: "Остановка {current} из {total}",
            stopWaitingDesc: "Стойте 10 секунд. Если уехать с точки, отсчёт начнётся заново.", phase_toStop: "Следуйте к следующей остановке", phase_stopWaiting: "Ожидание на остановке", progress_stop: "До остановки", progress_stopWaiting: "Остановка",
            penalty_pickupDelay: "Опоздание к пассажиру", detail_pickupDelay: "Срок подачи превышен на {time}", notify_pickupLate: "Вы опоздали к пассажиру. Оплата снижена.", notify_multiStopStarted: "Пассажир в машине · остановок: {count}", notify_stopComplete: "Остановка завершена. Продолжайте поездку."
          },
          de: {
            silentModeHelp: "Deaktiviert alle Töne der TaxiDriver-App.",
            passengerCalmness: "Gelassenheit des Fahrgasts", stopDemandTitle: "Der Fahrgast will aussteigen", stopDemandDesc: "Das Fahrzeug hält sicher an. Die Steuerung ist vorübergehend gesperrt.", forcedExitTitle: "Der Fahrgast steigt aus", forcedExitDesc: "Der Fahrgast hat die Fahrt vorzeitig beendet. Warten Sie, bis die Tür geschlossen ist.", ratingLoss: "Fahrerbewertung −{percent}%", phase_passengerStopDemand: "Fahrgast verlangt einen Stopp", phase_passengerForcedExit: "Fahrgast steigt vorzeitig aus",
            penaltyEvents: "Strafen", noViolations: "Keine Strafen",
            multiStopBadge: "STOPPS ×{count}",
            dashCalm: "Ruhe", dashPickup: "Abholung", dashStop: "Stopp", dashRush: "Eilfahrt", dashRating: "Bonus", dashLost: "Weg",
            offersDynamic: "{count} von {target} Angeboten", pickupWindow: "Abholung innerhalb {time}", pickupDeadline: "Abholfrist", pickupLate: "Fahrgast wartet · {time} verspätet",
            ratingBonusLine: "Bewertungsbonus +{percent}% · +{amount}", multiStopRide: "Fahrt mit Stopps", multiStopSummary: "{count} Stopps · je {time}", stopProgress: "Stopp {current} von {total}",
            stopWaitingDesc: "10 Sekunden stehen bleiben. Beim Wegfahren startet der Timer neu.", phase_toStop: "Zum nächsten Stopp fahren", phase_stopWaiting: "Warten am Stopp", progress_stop: "Zum Stopp", progress_stopWaiting: "Zwischenstopp",
            penalty_pickupDelay: "Verspätete Abholung", detail_pickupDelay: "Abholfrist um {time} überschritten", notify_pickupLate: "Abholfrist verpasst. Der Fahrpreis wurde reduziert.", notify_multiStopStarted: "Fahrgast an Bord · {count} geplante Stopps", notify_stopComplete: "Stopp abgeschlossen. Fahrt fortsetzen."
          },
          fr: {
            silentModeHelp: "Désactive tous les sons de l’application TaxiDriver.",
            passengerCalmness: "Calme du passager", stopDemandTitle: "Le passager veut descendre", stopDemandDesc: "Le véhicule s’arrête en sécurité. Les commandes sont temporairement verrouillées.", forcedExitTitle: "Le passager descend", forcedExitDesc: "Le passager a interrompu la course. Attendez la fermeture de la porte.", ratingLoss: "Note du chauffeur −{percent}%", phase_passengerStopDemand: "Le passager exige un arrêt", phase_passengerForcedExit: "Le passager descend avant l’arrivée",
            penaltyEvents: "Pénalités", noViolations: "Aucune pénalité",
            multiStopBadge: "ARRÊTS ×{count}",
            dashCalm: "Calme", dashPickup: "Prise", dashStop: "Arrêt", dashRush: "Urgent", dashRating: "Note", dashLost: "Perdu",
            offersDynamic: "{count} offres sur {target}", pickupWindow: "Prise en charge sous {time}", pickupDeadline: "Délai de prise en charge", pickupLate: "Passager en attente · retard {time}",
            ratingBonusLine: "Bonus de note +{percent}% · +{amount}", multiStopRide: "Course avec arrêts", multiStopSummary: "{count} arrêts · {time} par arrêt", stopProgress: "Arrêt {current} sur {total}",
            stopWaitingDesc: "Restez arrêté 10 secondes. Quitter le point relance le compteur.", phase_toStop: "Rejoignez le prochain arrêt", phase_stopWaiting: "Attente à l’arrêt", progress_stop: "Vers l’arrêt", progress_stopWaiting: "Arrêt en cours",
            penalty_pickupDelay: "Prise en charge tardive", detail_pickupDelay: "Délai dépassé de {time}", notify_pickupLate: "Délai de prise en charge dépassé. Le tarif est réduit.", notify_multiStopStarted: "Passager à bord · {count} arrêts prévus", notify_stopComplete: "Arrêt terminé. Continuez la course."
          },
          es: {
            silentModeHelp: "Desactiva todos los sonidos de la aplicación TaxiDriver.",
            passengerCalmness: "Calma del pasajero", stopDemandTitle: "El pasajero quiere bajar", stopDemandDesc: "El vehículo se está deteniendo de forma segura. Los controles están bloqueados temporalmente.", forcedExitTitle: "El pasajero está bajando", forcedExitDesc: "El pasajero terminó el viaje antes de tiempo. Espera a que se cierre la puerta.", ratingLoss: "Valoración del conductor −{percent}%", phase_passengerStopDemand: "El pasajero exige detenerse", phase_passengerForcedExit: "El pasajero baja antes de tiempo",
            penaltyEvents: "Penalizaciones", noViolations: "Sin penalizaciones",
            multiStopBadge: "PARADAS ×{count}",
            dashCalm: "Calma", dashPickup: "Recogida", dashStop: "Parada", dashRush: "Urgente", dashRating: "Nota", dashLost: "Perdido",
            offersDynamic: "{count} de {target} ofertas", pickupWindow: "Recogida en {time}", pickupDeadline: "Límite de recogida", pickupLate: "Pasajero esperando · retraso {time}",
            ratingBonusLine: "Bono por valoración +{percent}% · +{amount}", multiStopRide: "Viaje con paradas", multiStopSummary: "{count} paradas · {time} en cada una", stopProgress: "Parada {current} de {total}",
            stopWaitingDesc: "Permanece detenido 10 segundos. Alejarte reinicia el contador.", phase_toStop: "Ve a la siguiente parada", phase_stopWaiting: "Esperando en la parada", progress_stop: "Hasta la parada", progress_stopWaiting: "Parada en curso",
            penalty_pickupDelay: "Recogida tardía", detail_pickupDelay: "Límite superado por {time}", notify_pickupLate: "Llegaste tarde a la recogida. El pago se ha reducido.", notify_multiStopStarted: "Pasajero a bordo · {count} paradas previstas", notify_stopComplete: "Parada completada. Continúa el viaje."
          },
          pl: {
            silentModeHelp: "Wyłącza wszystkie dźwięki aplikacji TaxiDriver.",
            passengerCalmness: "Spokój pasażera", stopDemandTitle: "Pasażer chce wysiąść", stopDemandDesc: "Pojazd bezpiecznie się zatrzymuje. Sterowanie jest tymczasowo zablokowane.", forcedExitTitle: "Pasażer wysiada", forcedExitDesc: "Pasażer zakończył kurs przed czasem. Poczekaj na zamknięcie drzwi.", ratingLoss: "Ocena kierowcy −{percent}%", phase_passengerStopDemand: "Pasażer żąda zatrzymania", phase_passengerForcedExit: "Pasażer wysiada przed czasem",
            penaltyEvents: "Kary", noViolations: "Brak kar",
            multiStopBadge: "PRZYSTANKI ×{count}",
            dashCalm: "Spokój", dashPickup: "Odbiór", dashStop: "Postój", dashRush: "Pilne", dashRating: "Ocena", dashLost: "Utrata",
            offersDynamic: "{count} z {target} ofert", pickupWindow: "Odbiór w ciągu {time}", pickupDeadline: "Limit odbioru", pickupLate: "Pasażer czeka · spóźnienie {time}",
            ratingBonusLine: "Premia za ocenę +{percent}% · +{amount}", multiStopRide: "Kurs z przystankami", multiStopSummary: "Przystanki: {count} · po {time}", stopProgress: "Przystanek {current} z {total}",
            stopWaitingDesc: "Pozostań 10 sekund. Odjazd z punktu zeruje licznik.", phase_toStop: "Jedź do następnego przystanku", phase_stopWaiting: "Postój na przystanku", progress_stop: "Do przystanku", progress_stopWaiting: "Postój",
            penalty_pickupDelay: "Spóźniony odbiór", detail_pickupDelay: "Limit przekroczony o {time}", notify_pickupLate: "Spóźniono się po pasażera. Zapłata została obniżona.", notify_multiStopStarted: "Pasażer w pojeździe · zaplanowane przystanki: {count}", notify_stopComplete: "Postój zakończony. Kontynuuj kurs."
          },
          uk: {
            silentModeHelp: "Вимикає всі звуки застосунку TaxiDriver.",
            passengerCalmness: "Спокій пасажира", stopDemandTitle: "Пасажир вимагає зупинитися", stopDemandDesc: "Автомобіль безпечно зупиняється. Керування тимчасово заблоковано.", forcedExitTitle: "Пасажир виходить", forcedExitDesc: "Пасажир достроково завершив поїздку. Дочекайтеся закриття дверей.", ratingLoss: "Рейтинг водія −{percent}%", phase_passengerStopDemand: "Пасажир вимагає зупинитися", phase_passengerForcedExit: "Пасажир достроково виходить",
            penaltyEvents: "Штрафи", noViolations: "Штрафів немає",
            multiStopBadge: "ЗУПИНКИ ×{count}",
            dashCalm: "Спокій", dashPickup: "Подача", dashStop: "Зупинка", dashRush: "Терміново", dashRating: "Рейтинг", dashLost: "Втрачено",
            offersDynamic: "{count} із {target} пропозицій", pickupWindow: "Подати авто за {time}", pickupDeadline: "Строк подачі", pickupLate: "Пасажир чекає · запізнення {time}",
            ratingBonusLine: "Бонус за рейтинг +{percent}% · +{amount}", multiStopRide: "Поїздка із зупинками", multiStopSummary: "Зупинок: {count} · по {time} на кожній", stopProgress: "Зупинка {current} із {total}",
            stopWaitingDesc: "Стійте 10 секунд. Якщо від’їхати, відлік почнеться знову.", phase_toStop: "Прямуйте до наступної зупинки", phase_stopWaiting: "Очікування на зупинці", progress_stop: "До зупинки", progress_stopWaiting: "Зупинка",
            penalty_pickupDelay: "Запізнення до пасажира", detail_pickupDelay: "Строк подачі перевищено на {time}", notify_pickupLate: "Ви запізнилися до пасажира. Оплату знижено.", notify_multiStopStarted: "Пасажир в авто · зупинок: {count}", notify_stopComplete: "Зупинку завершено. Продовжуйте поїздку."
          }
        };
        Object.keys(featureI18n).forEach((language) => Object.assign(i18n[language], featureI18n[language]));

        const settingsKey = "taxiDriverHUD.settings.v1";
        const languages = [
          { code: "en", label: "English" }, { code: "de", label: "Deutsch" },
          { code: "fr", label: "Français" }, { code: "es", label: "Español" },
          { code: "pl", label: "Polski" }, { code: "uk", label: "Українська" },
          { code: "ru", label: "Русский" },
        ];
        const difficulties = ["elementary", "easy", "standard", "professional"];
        let persisted = {};
        let legacySettingsFound = false;
        try {
          const legacyValue = localStorage.getItem(settingsKey);
          if (legacyValue) {
            const parsed = JSON.parse(legacyValue);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
              persisted = parsed;
              legacySettingsFound = true;
            }
          }
        } catch (_) { persisted = {}; }
        const initialLanguage = persisted.rememberLanguage && i18n[persisted.language] ? persisted.language : "en";
        const initialDifficulty = difficulties.includes(persisted.difficulty) ? persisted.difficulty : "standard";
        const savedFontBoost = persisted.fontBoost === undefined ? 2 : persisted.fontBoost;
        const initialFontBoost = Math.max(0, Math.min(5, Number(savedFontBoost)));
        const initialSilentMode = persisted.silentMode === true;
        const initialShowRouteGuidance = persisted.showRouteGuidance !== false;

        $scope.languages = languages;
        $scope.difficulties = difficulties;
        $scope.language = initialLanguage;
        $scope.settingsOpen = false;
        $scope.settingsSaved = false;
        $scope.phoneMinimized = false;
        $scope.phoneToast = null;
        $scope.passengerChat = null;
        $scope.nextOfferAcceptedVisible = false;
        $scope.settings = {
          language: initialLanguage,
          rememberLanguage: persisted.rememberLanguage === true,
          difficulty: initialDifficulty,
          fontBoost: initialFontBoost,
          silentMode: initialSilentMode,
          showRouteGuidance: initialShowRouteGuidance,
        };

        $scope.t = (key, values) => {
          const dictionary = i18n[$scope.language] || i18n.en;
          let text = dictionary[key] || i18n.en[key] || key;
          Object.keys(values || {}).forEach((name) => {
            text = text.split(`{${name}}`).join(String(values[name]));
          });
          return text;
        };

        const emptyPenalties = () => ({
          speedingPercent: 0,
          collisionPercent: 0,
          aggressionPercent: 0,
          pickupPercent: 0,
          speedingEvents: 0,
          collisions: 0,
          aggressionEvents: 0,
        });

        $scope.state = {
          active: false,
          phase: "inactive",
          phaseLabel: "",
          message: "",
          balance: 0,
          rating: 5,
          ratingCount: 0,
          completedRides: 0,
          offers: [],
          offerTargetCount: 10,
          penaltyEvents: [],
          activeTripId: 0,
          passengerName: "",
          passengerCalmness: 50,
          passengerStressPercent: 0,
          forcedExitDuration: 5,
          forcedExitRemaining: 0,
          earlyExitRatingLossPercent: 0,
          estimatedFare: 0,
          adjustedFare: 0,
          rideDistance: 0,
          distanceToTarget: 0,
          etaMinutes: 0,
          rideEtaMinutes: 0,
          pickupWaitLimit: 0,
          pickupTimeRemaining: 0,
          pickupLate: false,
          pickupLateSeconds: 0,
          ratingBonusPercent: 0,
          ratingBonusAmount: 0,
          isMultiStop: false,
          stopCount: 0,
          currentStopIndex: 0,
          stopProgressMarkers: [],
          stopWaitDuration: 10,
          stopWaitRemaining: 0,
          routeProgress: 0,
          progressLabel: "",
          rushOrder: false,
          rushBonusActive: false,
          rushBonusLost: false,
          rushBonusAmount: 0,
          rushTimeLimit: 0,
          rushTimeRemaining: 0,
          penaltyPercent: 0,
          speedLimit: 0,
          currentSpeed: 0,
          nextOffer: null,
          penalties: emptyPenalties(),
        };
        $scope.stars = [1, 2, 3, 4, 5];

        const createAppAudioPool = (fileName, volume, size) => {
          const players = [];
          for (let index = 0; index < size; index += 1) {
            const audio = new Audio(`/ui/modules/apps/TaxiDriverHUD/sounds/${fileName}`);
            audio.preload = "auto";
            audio.volume = volume;
            players.push(audio);
          }
          return { players, cursor: 0, baseVolume: volume };
        };
        const appAudio = {
          click: createAppAudioPool("taxidriver_ui_click.mp3", 0.52, 3),
          newRide: createAppAudioPool("taxidriver_new_ride.mp3", 0.78, 2),
          offline: createAppAudioPool("taxidriver_offline.mp3", 0.75, 2),
          online: createAppAudioPool("taxidriver_online.mp3", 0.75, 2),
          violation: createAppAudioPool("taxidriver_violation_ping.mp3", 0.7, 3),
          message: createAppAudioPool("taxidriver_passenger_message.mp3", 0.72, 3),
        };
        const passengerEmojiMoods = [
          {
            id: "cheerful",
            messages: ["☀️ 😊 ✨", "🌈 😄 🙌", "🎶 🚕 😎", "🌻 😁 💛", "🍀 😊 🛣️", "🌤️ 😄 🎵"],
          },
          {
            id: "sad",
            messages: ["🌧️ 😔 💭", "☁️ 😢 🫶", "🥀 😞 🕰️", "🌙 😔 💙", "🫥 🌧️ 🪟", "💧 😢 🌫️"],
          },
          {
            id: "excited",
            messages: ["🚕 🤩 🎉", "⚡ 😆 🙌", "🛣️ 🔥 😎", "🎊 🥳 ✨", "🏁 🤩 💫", "🚀 😄 🎶"],
          },
          {
            id: "sleepy",
            messages: ["🌙 😴 💤", "☕ 🥱 ⏳", "🛌 😪 🌧️", "🌌 😴 🚕", "🥱 💤 🫠", "🌙 ☕ 😪"],
          },
          {
            id: "dreamy",
            messages: ["🌸 ☺️ 💫", "🌆 🥰 🎶", "💐 😊 🌤️", "🦋 😌 💜", "🌌 🙂 ✨", "🌷 ☺️ 🎧"],
          },
          {
            id: "grumpy",
            messages: ["⏰ 😑 👀", "🚕 🫤 ⌛", "🌧️ 🙄 🕰️", "📍 😒 ⏳", "👀 🚕 😐", "⌛ 😤 🌫️"],
          },
        ];
        const passengerChatDisplayMs = 1800;
        let penaltyTrackingReady = false;
        let knownPenaltyEventIds = new Set();
        let lastPhoneNotificationId = 0;
        let phoneToastTimer = null;
        let acceptedOfferTimer = null;
        let trackedNextOfferId = null;
        let nextOfferDeadline = 0;
        const expiredNextOfferIds = new Set();
        $scope.nextOfferUiRemaining = 0;
        let settingsInitializedFromBackend = false;
        let legacyImportRequested = false;
        let hudStateReceived = false;
        let lastAnnouncedNextOfferId = null;
        let passengerChatTimer = null;
        let passengerChatHideTimer = null;
        let passengerChatGeneration = 0;
        let passengerChatTripId = 0;
        let passengerChatPassenger = "";
        let passengerChatMood = null;
        let passengerChatLastMessage = -1;
        let passengerChatMessageTarget = 0;
        let passengerChatMessageCount = 0;
        let gameUiVolume = 1;

        const clampAudioVolume = (value) => Math.max(0, Math.min(1, Number(value) || 0));
        const applyGameUiVolume = () => {
          Object.keys(appAudio).forEach((soundId) => {
            const pool = appAudio[soundId];
            const volume = clampAudioVolume(pool.baseVolume * gameUiVolume);
            pool.players.forEach((audio) => { audio.volume = volume; });
          });
        };
        const setGameUiVolume = (value) => {
          const parsed = Number(value);
          if (!Number.isFinite(parsed)) return;
          gameUiVolume = clampAudioVolume(parsed);
          applyGameUiVolume();
        };
        const refreshGameUiVolume = () => {
          bngApi.engineLua('settings.getValue("AudioUiVol")', setGameUiVolume);
        };

        const playAppSound = (soundId) => {
          if ($scope.settings.silentMode) return;
          const pool = appAudio[soundId];
          if (!pool || !pool.players.length) return;
          const audio = pool.players[pool.cursor];
          pool.cursor = (pool.cursor + 1) % pool.players.length;
          try {
            audio.volume = clampAudioVolume(pool.baseVolume * gameUiVolume);
            audio.currentTime = 0;
            const playback = audio.play();
            if (playback && playback.catch) playback.catch(() => {});
          } catch (_) {}
        };
        const playViolationSound = () => playAppSound("violation");

        const randomDelay = (minimum, maximum) =>
          minimum + Math.random() * Math.max(0, maximum - minimum);
        const isPassengerChatEligible = () =>
          $scope.state.active === true &&
          $scope.state.phase === "toPickup" &&
          Number($scope.state.activeTripId || 0) > 0 &&
          String($scope.state.passengerName || "").length > 0;
        const dismissPassengerChat = () => {
          if (passengerChatHideTimer) clearTimeout(passengerChatHideTimer);
          passengerChatHideTimer = null;
          $scope.passengerChat = null;
        };
        const stopPassengerChat = () => {
          passengerChatGeneration += 1;
          if (passengerChatTimer) clearTimeout(passengerChatTimer);
          passengerChatTimer = null;
          dismissPassengerChat();
          passengerChatTripId = 0;
          passengerChatPassenger = "";
          passengerChatMood = null;
          passengerChatLastMessage = -1;
          passengerChatMessageTarget = 0;
          passengerChatMessageCount = 0;
        };
        const schedulePassengerChat = (initial, requestedDelay) => {
          if (passengerChatTimer) clearTimeout(passengerChatTimer);
          passengerChatTimer = null;
          if (!isPassengerChatEligible() || !passengerChatMood ||
              passengerChatMessageCount >= passengerChatMessageTarget) return;
          const generation = passengerChatGeneration;
          const delay = requestedDelay === undefined
            ? randomDelay(initial ? 4500 : 7000, initial ? 7000 : 13000)
            : requestedDelay;
          passengerChatTimer = setTimeout(() => $scope.$evalAsync(() => {
            passengerChatTimer = null;
            if (generation !== passengerChatGeneration || !isPassengerChatEligible()) return;
            if ($scope.settingsOpen || $scope.phoneMinimized || $scope.phoneToast) {
              schedulePassengerChat(false, 2500);
              return;
            }

            const messages = passengerChatMood.messages;
            let messageIndex = Math.floor(Math.random() * messages.length);
            if (messages.length > 1 && messageIndex === passengerChatLastMessage) {
              messageIndex = (messageIndex + 1 + Math.floor(Math.random() * (messages.length - 1))) % messages.length;
            }
            passengerChatLastMessage = messageIndex;
            passengerChatMessageCount += 1;
            $scope.passengerChat = {
              passengerName: passengerChatPassenger,
              sentAt: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
              content: messages[messageIndex],
              mood: passengerChatMood.id,
            };
            playAppSound("message");
            passengerChatHideTimer = setTimeout(() => $scope.$evalAsync(() => {
              passengerChatHideTimer = null;
              $scope.passengerChat = null;
              if (generation === passengerChatGeneration && isPassengerChatEligible() &&
                  passengerChatMessageCount < passengerChatMessageTarget) {
                schedulePassengerChat(false);
              }
            }), passengerChatDisplayMs);
          }), delay);
        };
        const syncPassengerChat = () => {
          if (!isPassengerChatEligible()) {
            if (passengerChatPassenger || passengerChatTimer || $scope.passengerChat) stopPassengerChat();
            return;
          }
          const tripId = Number($scope.state.activeTripId || 0);
          const passengerName = String($scope.state.passengerName || "");
          if (tripId === passengerChatTripId && passengerName === passengerChatPassenger && passengerChatMood) {
            if (!passengerChatTimer && !$scope.passengerChat &&
                passengerChatMessageCount < passengerChatMessageTarget) {
              schedulePassengerChat(false, 2500);
            }
            return;
          }
          stopPassengerChat();
          passengerChatGeneration += 1;
          passengerChatTripId = tripId;
          passengerChatPassenger = passengerName;
          passengerChatMood = passengerEmojiMoods[Math.floor(Math.random() * passengerEmojiMoods.length)];
          passengerChatMessageTarget = 1 + Math.floor(Math.random() * 3);
          passengerChatMessageCount = 0;
          schedulePassengerChat(true);
        };

        const appRoot = $element[0];
        const handleAppClick = (event) => {
          let target = event.target;
          while (target && target !== appRoot) {
            const tagName = String(target.tagName || "").toLowerCase();
            if (tagName === "button" || tagName === "input" || tagName === "select") {
              playAppSound("click");
              return;
            }
            target = target.parentElement;
          }
        };
        appRoot.addEventListener("click", handleAppClick, true);

        const callTaxiDriver = (functionName) => {
          bngApi.engineLua(
            `if not taxiDriver_taxiDriver then extensions.load("taxiDriver_taxiDriver") end; taxiDriver_taxiDriver.${functionName}()`
          );
        };

        const clearNextOfferCountdown = () => {
          trackedNextOfferId = null;
          nextOfferDeadline = 0;
          $scope.nextOfferUiRemaining = 0;
        };

        const expireNextOfferLocally = (offerId) => {
          const id = Math.floor(Number(offerId || 0));
          if (id <= 0 || expiredNextOfferIds.has(id)) return;
          expiredNextOfferIds.add(id);
          clearNextOfferCountdown();
          if ($scope.state.nextOffer && Number($scope.state.nextOffer.id) === id &&
              !$scope.state.nextOffer.accepted) {
            $scope.state = Object.assign({}, $scope.state, { nextOffer: null });
          }
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.expireNextOffer(${id}) end`
          );
        };

        const updateNextOfferCountdown = () => {
          if (!trackedNextOfferId) return;
          const remaining = Math.max(0, (nextOfferDeadline - Date.now()) / 1000);
          $scope.$evalAsync(() => {
            $scope.nextOfferUiRemaining = remaining;
            if (remaining <= 0 && trackedNextOfferId) {
              expireNextOfferLocally(trackedNextOfferId);
            }
          });
        };

        const syncNextOfferCountdown = (offer) => {
          if (!offer || offer.accepted) {
            clearNextOfferCountdown();
            return;
          }
          const id = Math.floor(Number(offer.id || 0));
          if (id <= 0 || expiredNextOfferIds.has(id)) return;
          if (trackedNextOfferId === id) return;
          trackedNextOfferId = id;
          const remaining = Math.max(0, Number(offer.timeRemaining || offer.duration || 5));
          nextOfferDeadline = Date.now() + remaining * 1000;
          $scope.nextOfferUiRemaining = remaining;
        };

        const normalizeSettings = (source) => {
          const value = source && typeof source === "object" ? source : {};
          const fontBoost = value.fontBoost === undefined ? 2 : Number(value.fontBoost);
          return {
            language: i18n[value.language] ? value.language : "en",
            rememberLanguage: value.rememberLanguage === true,
            difficulty: difficulties.includes(value.difficulty) ? value.difficulty : "standard",
            fontBoost: Math.max(0, Math.min(5, Math.round(Number.isFinite(fontBoost) ? fontBoost : 2))),
            silentMode: value.silentMode === true,
            showRouteGuidance: value.showRouteGuidance !== false,
          };
        };

        const saveSettingsToLua = (source) => {
          const luaSettings = bngApi.serializeToLua(normalizeSettings(source));
          bngApi.engineLua(
            `if not taxiDriver_taxiDriver then extensions.load("taxiDriver_taxiDriver") end; taxiDriver_taxiDriver.saveSettings(${luaSettings})`
          );
        };

        let lastMinimapRect = "";
        let minimapVisible = false;
        let uiVisible = true;
        const minimapPhases = new Set(["toPickup", "toStop", "toDestination"]);
        const canRenderMinimap = (hudState) => uiVisible && !$scope.phoneMinimized &&
          !$scope.settingsOpen && hudState && hudState.active === true &&
          minimapPhases.has(hudState.phase);
        const hideMinimap = (force) => {
          if (!force && !minimapVisible && !lastMinimapRect) return;
          lastMinimapRect = "";
          minimapVisible = false;
          bngApi.engineLua(
            "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.hideMinimap() end"
          );
        };

        const updateMinimap = () => {
          if (!canRenderMinimap($scope.state)) {
            hideMinimap();
            return;
          }

          const surface = $element[0].querySelector(".taxi-minimap-surface");
          if (!surface) {
            hideMinimap();
            return;
          }

          const rect = surface.getBoundingClientRect();
          if (rect.width < 20 || rect.height < 20 || window.innerWidth <= 0 || window.innerHeight <= 0) return;

          const normalizeRect = (element) => {
            if (!element) return [0, 0, 0, 0];
            const elementRect = element.getBoundingClientRect();
            const left = Math.max(0, Math.min(window.innerWidth, elementRect.left + window.scrollX));
            const top = Math.max(0, Math.min(window.innerHeight, elementRect.top + window.scrollY));
            const right = Math.max(left, Math.min(window.innerWidth, elementRect.right + window.scrollX));
            const bottom = Math.max(top, Math.min(window.innerHeight, elementRect.bottom + window.scrollY));
            return [
              left / window.innerWidth,
              top / window.innerHeight,
              (right - left) / window.innerWidth,
              (bottom - top) / window.innerHeight,
            ];
          };

          const values = normalizeRect(surface);
          const routeInfoValues = normalizeRect($element[0].querySelector(".taxi-map__route-info"));
          const speedLimitValues = normalizeRect($element[0].querySelector(".taxi-map__speed"));
          const notificationValues = normalizeRect($element[0].querySelector(".taxi-phone-toast"));
          const layoutKey = values
            .concat(routeInfoValues, speedLimitValues, notificationValues)
            .map((value) => value.toFixed(5))
            .join(",");
          if (layoutKey === lastMinimapRect) return;
          lastMinimapRect = layoutKey;
          minimapVisible = true;

          const rectKey = values.map((value) => value.toFixed(5)).join(",");
          const occlusionKey = routeInfoValues
            .concat(speedLimitValues, notificationValues)
            .map((value) => value.toFixed(5))
            .join(",");

          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.setMinimapTransform(${rectKey}); taxiDriver_taxiDriver.setMinimapOcclusions(${occlusionKey}) end`
          );
        };

        const scheduleMinimapUpdate = () =>
          $scope.$evalAsync(() => requestAnimationFrame(updateMinimap));

        const updateClock = () => {
          $scope.currentClock = new Date().toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
          });
        };

        this.startMode = () => callTaxiDriver("startMode");
        this.stopMode = () => callTaxiDriver("stopMode");
        this.toggleMinimized = () => {
          $scope.phoneMinimized = !$scope.phoneMinimized;
          if ($scope.phoneMinimized) {
            dismissPassengerChat();
            hideMinimap();
          }
          else scheduleMinimapUpdate();
        };
        this.toggleSettings = () => {
          $scope.settingsOpen = !$scope.settingsOpen;
          $scope.settingsSaved = false;
          if ($scope.settingsOpen) {
            dismissPassengerChat();
            hideMinimap();
          }
          else scheduleMinimapUpdate();
        };
        this.selectLanguage = (languageCode) => {
          if (!i18n[languageCode]) return;
          $scope.settings.language = languageCode;
          $scope.language = languageCode;
          $scope.settingsSaved = false;
        };
        this.selectDifficulty = (preset) => {
          if (difficulties.includes(preset)) $scope.settings.difficulty = preset;
          $scope.settingsSaved = false;
        };
        this.saveSettings = () => {
          $scope.settings = normalizeSettings($scope.settings);
          $scope.language = $scope.settings.language;
          saveSettingsToLua($scope.settings);
          $scope.settingsSaved = true;
          $scope.settingsOpen = false;
          scheduleMinimapUpdate();
        };
        this.acceptOrder = (offerId) => {
          const id = Math.floor(Number(offerId || 0));
          if (id <= 0) return;
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.acceptOrder(${id}) end`
          );
        };
        this.acceptNextOffer = (offerId) => {
          const id = Math.floor(Number(offerId || 0));
          if (id <= 0) return;
          if ($scope.nextOfferUiRemaining <= 0) {
            expireNextOfferLocally(id);
            return;
          }
          clearNextOfferCountdown();
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.acceptNextOffer(${id}) end`
          );
        };

        $scope.formatMoney = (value) => `$${Number(value || 0).toFixed(2)}`;
        $scope.formatDistance = (meters) => {
          const value = Number(meters || 0);
          return value >= 1000
            ? `${(value / 1000).toFixed(1)} ${$scope.t("unitKm")}`
            : `${Math.max(0, Math.round(value))} ${$scope.t("unitMeter")}`;
        };
        $scope.formatEta = (minutes) => {
          const value = Math.max(0, Number(minutes || 0));
          if (value < 1) return `< 1 ${$scope.t("unitMin")}`;
          if (value < 60) return `${Math.ceil(value)} ${$scope.t("unitMin")}`;
          const hours = Math.floor(value / 60);
          return `${hours} ${$scope.t("unitHour")} ${Math.ceil(value - hours * 60)} ${$scope.t("unitMin")}`;
        };
        $scope.formatCountdown = (seconds) => {
          const value = Math.max(0, Math.ceil(Number(seconds || 0)));
          const minutes = Math.floor(value / 60);
          return `${minutes}:${String(value % 60).padStart(2, "0")}`;
        };
        $scope.getArrivalTime = (minutes) => {
          const arrival = new Date(Date.now() + Math.max(0, Number(minutes || 0)) * 60000);
          return arrival.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
        };
        $scope.getInitials = (name) =>
          String(name || "P")
            .split(/\s+/)
            .slice(0, 2)
            .map((part) => part.charAt(0).toUpperCase())
            .join("");
        $scope.getCalmnessEmoji = (value) => {
          const numeric = Number(value);
          const calmness = Number.isFinite(numeric)
            ? Math.max(0, Math.min(100, numeric))
            : 50;
          if (calmness < 15) return "😤";
          if (calmness < 30) return "😠";
          if (calmness < 45) return "😟";
          if (calmness < 60) return "😐";
          if (calmness < 75) return "🙂";
          if (calmness < 90) return "😌";
          return "😇";
        };
        $scope.getProgressPercent = () =>
          Math.max(0, Math.min(100, Number($scope.state.routeProgress || 0) * 100));
        $scope.getStarFill = (star) => {
          const rating = Number($scope.state.rating || 0);
          return Math.max(0, Math.min(100, (rating - (star - 1)) * 100));
        };
        $scope.getRatingPercent = () =>
          Math.max(0, Math.min(100, Number($scope.state.rating || 0) / 5 * 100));
        $scope.getFontPercent = () => 100 + Number($scope.settings.fontBoost || 0) * 10;
        $scope.formatRating = (value) => Number(value || 0).toFixed(2);
        $scope.formatBonusPercent = (value) => Number(value || 0).toFixed(1).replace(/\.0$/, "");
        $scope.shouldShowNextOffer = () => {
          const offer = $scope.state.nextOffer;
          if (!offer || $scope.state.phase !== "toDestination") return false;
          return offer.accepted ? $scope.nextOfferAcceptedVisible : $scope.nextOfferUiRemaining > 0;
        };
        $scope.shouldShowQueuedOrder = () => {
          const offer = $scope.state.nextOffer;
          if (!offer || offer.accepted !== true) return false;
          const activeTripId = Number($scope.state.activeTripId || 0);
          const queuedTripIsCurrent = activeTripId > 0 && Number(offer.id || 0) === activeTripId;
          return !queuedTripIsCurrent || $scope.state.phase === "toPickup";
        };
        $scope.getPhaseLabel = () => $scope.t(`phase_${$scope.state.phase || "inactive"}`);
        $scope.getProgressLabel = () => {
          const map = {
            toPickup: "progress_pickup", boarding: "progress_boarding",
            toStop: "progress_stop", stopWaiting: "progress_stopWaiting",
            toDestination: "progress_ride", alighting: "progress_alighting",
          };
          return $scope.t(map[$scope.state.phase] || "progress_route");
        };
        $scope.getStatusText = () => {
          if ($scope.state.phase === "searching") {
            return $scope.state.offers.length
              ? $scope.t("offersDynamic", {
                  count: $scope.state.offers.length,
                  target: $scope.state.offerTargetCount,
                })
              : $scope.t("connecting");
          }
          return $scope.t("followRoute");
        };
        $scope.getPenaltyLabel = (event) => $scope.t(`penalty_${event.kind || "speeding"}`);
        $scope.getPhoneNotificationText = () => $scope.phoneToast
          ? $scope.t($scope.phoneToast.key, $scope.phoneToast.values || {})
          : "";
        $scope.getPenaltyDetail = (event) => {
          if (event.kind === "speeding") return $scope.t("detail_speeding", {
            speed: Number(event.speedExcess || 0).toFixed(0),
            duration: Number(event.duration || 0).toFixed(1),
          });
          if (event.kind === "collision") return $scope.t("detail_collision", {
            damage: Number(event.damage || 0).toFixed(0),
          });
          if (event.kind === "aggression") return $scope.t("detail_aggression", {
            g: Number(event.peakG || 0).toFixed(2),
          });
          if (event.kind === "bonus") return $scope.t("detail_bonus");
          if (event.kind === "pickupDelay") return $scope.t("detail_pickupDelay", {
            time: $scope.formatCountdown(event.lateSeconds || 0),
          });
          return event.detail || "";
        };
        $scope.getQuality = () =>
          Math.max(50, 100 - Number($scope.state.penaltyPercent || 0));

        $scope.$on("TaxiDriverHUDState", (_, data) => {
          if (!data) return;
          const pickupJustStarted = data.phase === "boarding" && $scope.state.phase === "toPickup";
          if (pickupJustStarted) {
            $scope.nextOfferAcceptedVisible = false;
            if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
            acceptedOfferTimer = null;
            if ($scope.phoneToast && $scope.phoneToast.key === "notify_orderAccepted") {
              $scope.phoneToast = null;
              if (phoneToastTimer) clearTimeout(phoneToastTimer);
              phoneToastTimer = null;
            }
          }
          if (data.settings) {
            const backendSettings = normalizeSettings(data.settings);
            if (data.settingsNeedsLegacyImport && !legacyImportRequested) {
              legacyImportRequested = true;
              saveSettingsToLua(legacySettingsFound ? persisted : backendSettings);
            } else if (!data.settingsNeedsLegacyImport && !settingsInitializedFromBackend) {
              if (!backendSettings.rememberLanguage) backendSettings.language = "en";
              $scope.settings = backendSettings;
              $scope.language = backendSettings.language;
              settingsInitializedFromBackend = true;
              try { localStorage.removeItem(settingsKey); } catch (_) {}
            }
          }
          if (data.nextOffer && expiredNextOfferIds.has(Number(data.nextOffer.id))) {
            data.nextOffer = null;
          }
          syncNextOfferCountdown(data.nextOffer);
          const incomingNextOfferId = data.nextOffer ? Number(data.nextOffer.id || 0) : 0;
          const hasNewNextOffer = hudStateReceived && incomingNextOfferId > 0 &&
            data.nextOffer.accepted !== true && incomingNextOfferId !== lastAnnouncedNextOfferId;
          if (incomingNextOfferId > 0) lastAnnouncedNextOfferId = incomingNextOfferId;
          const hasNewAcceptedOffer = !pickupJustStarted && data.nextOffer && data.nextOffer.accepted &&
            (!$scope.state.nextOffer || !$scope.state.nextOffer.accepted);
          const hasNewNotification = data.notification && data.notification.id !== lastPhoneNotificationId &&
            !(pickupJustStarted && data.notification.key === "notify_orderAccepted");
          const becameOnline = hudStateReceived && data.active === true && $scope.state.active !== true;
          const becameOffline = hudStateReceived && data.active === false && $scope.state.active === true;
          if (becameOnline) playAppSound("online");
          if (becameOffline) playAppSound("offline");
          if (hasNewNextOffer) playAppSound("newRide");
          if ((hasNewNextOffer || hasNewNotification) && $scope.phoneMinimized) {
            $scope.phoneMinimized = false;
          }
          if (hasNewNotification) {
            dismissPassengerChat();
            lastPhoneNotificationId = data.notification.id;
            $scope.phoneToast = data.notification;
            if (phoneToastTimer) clearTimeout(phoneToastTimer);
            phoneToastTimer = setTimeout(() => $scope.$evalAsync(() => {
              $scope.phoneToast = null;
              phoneToastTimer = null;
            }), 3600);
          }
          if (hasNewAcceptedOffer) {
            $scope.nextOfferAcceptedVisible = true;
            if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
            acceptedOfferTimer = setTimeout(() => $scope.$evalAsync(() => {
              $scope.nextOfferAcceptedVisible = false;
              acceptedOfferTimer = null;
            }), 1200);
          }
          // Empty Lua tables are serialized as objects, not JavaScript arrays.
          // Normalize list fields before using array methods or binding them in Angular.
          const penaltyEvents = Array.isArray(data.penaltyEvents) ? data.penaltyEvents : [];
          data.penaltyEvents = penaltyEvents;
          data.offers = Array.isArray(data.offers) ? data.offers : [];
          data.stopProgressMarkers = Array.isArray(data.stopProgressMarkers)
            ? data.stopProgressMarkers
            : [];
          const penaltyPhase = ["toPickup", "toStop", "toDestination", "passengerStopDemand"].includes(data.phase);
          if (!penaltyPhase) {
            penaltyTrackingReady = false;
            knownPenaltyEventIds = new Set();
          } else if (!penaltyTrackingReady) {
            knownPenaltyEventIds = new Set(penaltyEvents.map((event) => event.id));
            penaltyTrackingReady = true;
          } else {
            const hasNewPenalty = penaltyEvents.some((event) => !knownPenaltyEventIds.has(event.id));
            penaltyEvents.forEach((event) => knownPenaltyEventIds.add(event.id));
            if (hasNewPenalty) playViolationSound();
          }
          data.penalties = Object.assign(emptyPenalties(), data.penalties || {});
          $scope.state = Object.assign({}, $scope.state, data);
          syncPassengerChat();
          hudStateReceived = true;
          lastMinimapRect = "";
          if (canRenderMinimap($scope.state)) scheduleMinimapUpdate();
          else hideMinimap(minimapVisible);
        });
        $scope.$on("onCefVisibilityChanged", (_, visible) => {
          uiVisible = visible !== false;
          if (uiVisible) {
            refreshGameUiVolume();
            scheduleMinimapUpdate();
          }
          else hideMinimap();
        });
        $scope.$on("SettingsChanged", (_, data) => {
          const value = data && data.values ? data.values.AudioUiVol : undefined;
          if (value === undefined) refreshGameUiVolume();
          else setGameUiVolume(value);
        });

        updateClock();
        refreshGameUiVolume();
        const clockTimer = setInterval(() => $scope.$evalAsync(updateClock), 30000);
        const minimapTimer = setInterval(updateMinimap, 500);
        const nextOfferCountdownTimer = setInterval(updateNextOfferCountdown, 50);
        window.addEventListener("resize", updateMinimap);
        $scope.$on("$destroy", () => {
          clearInterval(clockTimer);
          clearInterval(minimapTimer);
          clearInterval(nextOfferCountdownTimer);
          if (phoneToastTimer) clearTimeout(phoneToastTimer);
          if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
          stopPassengerChat();
          appRoot.removeEventListener("click", handleAppClick, true);
          window.removeEventListener("resize", updateMinimap);
          hideMinimap();
        });
        callTaxiDriver("requestHudState");
        scheduleMinimapUpdate();
      },
    };
  },
]);
