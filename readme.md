# Smart Contract: Auction

Repositorio: https://github.com/nrmattar-dev/ETHKipu2025/tree/main/contracts
Contrato: https://sepolia.etherscan.io/address/0x208166e542b6e7273A90b3C86590AE99dEe655cE

## Funcionalidades

- **Crear una subasta**: El dueño del contrato configura los parámetros iniciales de la subasta (como el monto mínimo de las ofertas, la duración, etc.).
- **Hacer una oferta**: Los participantes pueden hacer ofertas mayores que el valor actual de la subasta, y se valida que el monto cumpla con el porcentaje de incremento mínimo (`bidGap`).
- **Extensión de la subasta**: Si se hace una oferta dentro de un cierto rango de tiempo al final de la subasta, la duración de la subasta se extiende.
- **Finalizar la subasta**: El dueño del contrato puede finalizar la subasta, procesar los pagos y devolver las ofertas a los postores no ganadores.
- **Reembolsos parciales**: Los postores pueden recuperar una parte de su dinero si no ganaron la subasta y si tienen una cantidad superior a su última oferta realizada.

## Variables

- **`active`** (`bool`): Indica si la subasta está activa o no. Si es `false`, no se pueden realizar acciones.
- **`seller`** (`address`): La dirección del vendedor que recibirá el monto total de la oferta ganadora al final de la subasta.
- **`owner`** (`address`): La dirección del dueño del contrato quien tiene la facultad de finalizar la subasta.
- **`bidGap`** (`uint256`): El porcentaje mínimo de aumento requerido entre las ofertas. Si una nueva oferta no es al menos dicho porcentaje mayor que la anterior, no se aceptará.
- **`gasCommissionPercentage`** (`uint256`): El porcentaje de la oferta de quienes no ganaron que se quedará el contrato al finalizar la subasta (para comisión del gas)
- **`initDate`** (`uint256`): La fecha y hora de inicio de la subasta (en formato epoch).
- **`finishDate`** (`uint256`): La fecha y hora de finalización de la subasta.
- **`bidExtensionZone`** (`uint256`): El margen de tiempo (en segundos) antes de la fecha de finalización donde en el caso de realizarse una oferta, se extiende la duración del contrato.
- **`bidExtensionTime`** (`uint256`): El tiempo (en segundos) que se añade al finalizar la subasta si se realiza una oferta en el lapso previamente nombrado.
- **`bids`** (`Bid[]`): Un array que contiene todas las ofertas realizadas. Cada oferta es de tipo "Bid".
- **`winnerBid`** (`Bid`): La oferta ganadora, la cual es un objeto de tipo `Bid` que contiene la dirección y el monto que ganó.
- **`bidAddressLastAmount`** (`mapping(address => uint256)`): Un mapping que guarda la última oferta realizada por cada address.
- **`bidAddressTotalAmount`** (`mapping(address => uint256)`): Un mapping que guarda el total acumulado de las ofertas realizadas por cada address.

## Estructuras de Datos

### `Bid`
struct Bid { 
    address bidder; // Address del postor
    uint256 amount; // Monto de la oferta
}


## Funciones:

- `MakeABid`: Sirve para hacer una puja:
El modifier isActive() valida que esté activa (que el owner no la haya terminado y repartido el dinero). El modifier isNotEnded() valida que se haga dentro del tiempo de la subasta.
Usé esos dos modifiers porque ambos contienen lógicas que se usan más de una vez.

function MakeABid () payable isActive() isNotEnded() external {
        
        //Valido que la oferta sea mayor a 0.
        require (msg.value > 0, "The amount must be higher than zero");

        /*
        Como Solidity no maneja decimales, en lugar de dividir para validar, debo multiplicar.
        Ejemplo: Si _amount es 200, maxBidAmount es 150 y bidGap es 5, entonces:
        200*100 >= 150 * (100 + 5)
        20000 >= 15750 --> OK
        */

		//Valido que el valor sea superior al menos un bidGap% que la oferta ganadora para tomarlo.
        require (msg.value*100 >= winnerBid.amount*(100 + bidGap), "The amount is not higher than the gap");
    
        //Guardo la información de este nuevo postor con su oferta superadora
        bidAddressLastAmount[msg.sender] = msg.value;
        bidAddressTotalAmount[msg.sender] += msg.value;
        bids.push(Bid(msg.sender,msg.value));

        //Actualizo la variable estructurada winnerBid con la info de la oferta superadora.
        winnerBid.amount = msg.value;
        winnerBid.bidder = msg.sender;

        //Emito el evento de que hay una oferta superadora
        emit NewOffer(msg.sender, msg.value);

        //Chequeo si está cerca del final de la subasta y, de ser así, corro la fecha de fin
        if (block.timestamp >= (finishDate-bidExtensionZone))
        {
            finishDate = block.timestamp + bidExtensionTime;
        }

    }  


- `EndAuction`: Sirve para finalizar la subasta. El modifier isActive verifica que la subasta no haya sido terminada por el owner. isEnded() que esté fuera de la duración de la subasta y onlyOwner() que sólo el owner pueda finalizarla.

function EndAuction () isActive() isEnded() onlyOwner() external {

	active = false;
	uint256 totalAmount = 0;
	uint256 refundAmount = 0;
	address bidder;

	//Recorro la colección de ofertantes
	for (uint i=0; i < bids.length; i++)
	{
	
		bidder = bids[i].bidder; //Cargo el address
		totalAmount = bidAddressTotalAmount[bidder]; //Cargo el monto total acumulado de todas sus ofertas
		
	//Si tiene dinero para transferir, procedo.
	if (totalAmount > 0) 
	{

		bidAddressTotalAmount[bidder] = 0; //Como le transfiero el total, vacío la variable para que no siga entrando (si tuvo diversas pujas, seguiría entrando).
	
		//Verifico si se trata o no del ganador.
		if (bidder != winnerBid.bidder) 
		{
			//si no es el ganador, le devuelvo el dinero descontándole la comisión del gas.
			refundAmount = totalAmount - ((totalAmount*gasCommissionPercentage)/100);
			(bool sent,) = payable(bidder).call{value: refundAmount}(""); //Transfiero
			require(sent, "Failed to refund"); //Si hubo error, revierto.                
		}
		else 
		{
			//si es el ganador, transfiero la totalidad al vendedor.
			(bool sent,) = payable(seller).call{value: totalAmount}(""); //Transfiero
			require(sent, "Failed to tranfer prize"); //Si hubo error, revierto.                
		}
		}

	}

	emit AuctionEnded(winnerBid);
}

- `PartialRefund`: Hace un reembolso parcial de las apuestas de los ofertantes. Si ofertó 3 veces, se le devuelve el acumulado de las primeras dos ofertas.

    function PartialRefund() external isActive() isNotEnded()  {
        uint256 lastAmount = bidAddressLastAmount[msg.sender];
        uint256 totalAmount = bidAddressTotalAmount[msg.sender];
		
		//Si el monto que tiene acumulado es 0, no hago nada porque significa que no se recibieron ofertas de él/ella
        if (totalAmount == 0)
        {
            revert("No bids were received from you"); 
        }

		//Si la última oferta es igual al acumulado entonces tampoco le devuelvo nada porque significa o que sólo hizo una oferta o que ya se le devolvió de forma parcial anteriormente.
        if (lastAmount == totalAmount)
        {
            revert("There is no partial amount to refund"); 
        }  

		uint256 partialAmount = totalAmount - lastAmount; //El total menos la ultima apuesta es lo que puede recuperar.
        bidAddressTotalAmount[msg.sender] -= partialAmount; //Resto el monto parcial (que se le va a devolver) de su total acumulado, así no puede pedir refund n veces.
        
		//Envío el dinero
        (bool sent,) = payable(msg.sender).call{value: partialAmount}(""); 
        require(sent, "Failed to refund"); //Si hubo error, revierto.

    }